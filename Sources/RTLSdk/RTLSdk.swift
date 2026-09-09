import Foundation
import UIKit
import WebKit
import CoreLocation
import SafariServices
import AuthenticationServices

public struct RTLExperienceResult {
    public let success: Bool
    public let errorCode: String?

    init(success: Bool, errorCode: String? = nil) {
        self.success = success
        self.errorCode = errorCode
    }
}

/// Where the web app wants a destination rendered.
///
/// All three keep the page out of host-controlled code; they differ in whether
/// the app is left, and whether the flow returns a result.
///
/// - `overlay`: an in-app browser for general browsing, any host. Merchant
///   pages belong here - an offer exit opens our redirect endpoint and lands on
///   the merchant, without leaving the app.
/// - `auth`: an overlay for a flow that comes back with a result, restricted to
///   the configured host. Used by card linking. Not for ordinary browsing: it
///   ends only on the return redirect, which a merchant never sends, and it
///   runs with an isolated cookie jar, so a shopper already signed in to that
///   merchant would not be.
/// - `providerAuth`: the same session, for a provider's own page. Open banking
///   linking runs at Plaid or Cardlytics, so the host cannot be ours, but the
///   flow still returns a result and needs the redirect captured.
/// - `external`: the system browser, leaving the app.
///
/// `auth` and `providerAuth` are separate values rather than one with a
/// relaxed check, because the restriction is the whole of what `auth` promises:
/// that card collection happens where the SDK says it does. A page asking for
/// `providerAuth` is stating that its destination is a third party, which is a
/// different claim and should read differently at the call site.
enum RTLSurface: String, CaseIterable {
    case overlay
    case auth
    case providerAuth
    case external
}

private enum RTLExperienceError: String {
    case token_unavailable
    case webview_not_created
    case invalid_token_forward_url
    case authentication_failed
    case login_timeout
    case request_cancelled
}

enum RTLDeepLinkRoute: Equatable {
    case open(rtlEventId: String?, rtlRedirectUrl: String?)
    case callback(URL)
}

func parseRTLDeepLink(_ url: URL, configuredScheme: String?) -> RTLDeepLinkRoute? {
    guard let configuredScheme,
          url.scheme?.caseInsensitiveCompare(configuredScheme) == .orderedSame,
          url.host?.caseInsensitiveCompare("rtl-sdk") == .orderedSame else {
        return nil
    }

    switch url.path {
    case "/open":
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let rtlRedirectUrl = items?
            .first(where: { $0.name == "rtlRedirectUrl" })?
            .value?
            .nilIfBlank
        let rtlEventId = rtlRedirectUrl == nil
            ? items?.first(where: { $0.name == "rtlEventId" })?.value?.nilIfBlank
            : nil
        return .open(rtlEventId: rtlEventId, rtlRedirectUrl: rtlRedirectUrl)
    case "/callback":
        return .callback(url)
    default:
        return nil
    }
}

private extension String {
    var nilIfBlank: String? {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self
    }
}

/// Main SDK singleton for RTL webview integration
public final class RTLSdk {

    /// Shared singleton instance
    public static let shared = RTLSdk()

    // MARK: - Configuration

    private var baseURL: URL?
    private var urlScheme: String?
    private var externalChapterId: String?
    private var isInitialized = false

    // MARK: - State

    private weak var webView: RTLWebView?

    /// When the current open began loading, for the one number that says how
    /// long an open takes. Cleared when it is reported, so a later navigation
    /// inside an already-open session is not counted as a fresh open.
    private var openStartedAt: Date?

    /// Retained for the life of the overlay. An ASWebAuthenticationSession
    /// that goes out of scope is cancelled, so this is what keeps it alive.
    private var overlaySession: ASWebAuthenticationSession?
    private let overlayAnchorProvider = RTLOverlayAnchorProvider()

    // MARK: - Location Services

    private var locationManager: RTLLocationManager?
    private var geofenceManager: RTLGeofenceManager?
    private var hyperlocalOffersService: RTLHyperlocalOffersService?
    private var notificationManager: RTLNotificationManager?
    private var locationFeaturesEnabled = false
    private var webviewAwaitingPermissionResponse = false
    private var webviewIsReady = false
    private var lastGeofenceFetchTime: Date?
    private let geofenceFetchDebounceInterval: TimeInterval = 5.0

    // MARK: - Async Login

    private final class AuthenticationAttempt {
        var continuation: CheckedContinuation<RTLExperienceResult, Never>?
        var tokenTask: Task<Void, Never>?
        var timeoutTask: Task<Void, Never>?
        var awaitingWeb = false
    }

    private var activeAttempt: AuthenticationAttempt?
    private let loginTimeout: TimeInterval = 30.0
    private var isExperienceLoading = false

    // MARK: - Delegate

    private weak var delegate: RTLSdkDelegate?

    // MARK: - Initialization

    private init() {}

    /// Initialize the SDK with configuration and delegate.
    /// - Parameters:
    ///   - baseURL: The complete HTTP(S) base URL supplied for this client
    ///   - urlScheme: The app's URL scheme for deep linking
    ///   - delegate: Delegate for receiving SDK events
    ///   - externalChapterId: The external chapter ID for location-based features (optional)
    public func initialize(
        baseURL: URL,
        urlScheme: String,
        delegate: RTLSdkDelegate,
        externalChapterId: String? = nil
    ) {
        cancelAuthentication()
        webView?.invalidateDocument()
        webviewIsReady = false
        webView?.isHidden = true
        self.baseURL = baseURL
        self.urlScheme = urlScheme
        self.delegate = delegate
        self.externalChapterId = externalChapterId
        self.isInitialized = true
    }

    // MARK: - Public API

    /// Creates an embeddable webview for the RTL experience
    /// - Returns: RTLWebView instance that can be added to your view hierarchy
    public func createWebView() -> RTLWebView {
        createWebView(using: { RTLWebView(sdk: $0) })
    }

    // Internal factory lets lifecycle tests record navigation without loading
    // remote documents. Host apps always use the real WebView above.
    func createWebView<View: RTLWebView>(using makeView: (RTLSdk) -> View) -> View {
        guard isInitialized else {
            fatalError("RTLSdk not initialized. Call initialize() first.")
        }
        cancelAuthentication()
        self.webView?.invalidateDocument()
        webviewIsReady = false
        let webView = makeView(self)
        webView.isHidden = true
        self.webView = webView
        return webView
    }

    /// Request token from delegate and perform login.
    /// Called for initial sign-in and explicit reauthentication.
    @MainActor
    public func presentExperience(
        rtlEventId: String? = nil,
        rtlRedirectUrl: String? = nil
    ) async -> RTLExperienceResult {
        let attempt = AuthenticationAttempt()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: .failure(.request_cancelled))
                    return
                }
                attempt.continuation = continuation
                startAuthentication(attempt, rtlEventId: rtlEventId, rtlRedirectUrl: rtlRedirectUrl)
            }
        } onCancel: {
            Task { @MainActor in
                self.finishAuthentication(attempt, result: .failure(.request_cancelled))
            }
        }
    }

    @MainActor
    private func startAuthentication(
        _ attempt: AuthenticationAttempt,
        rtlEventId: String? = nil,
        rtlRedirectUrl: String? = nil
    ) {
        beginAuthentication(attempt)
        updateExperienceLoading(true)
        let tokenProvider = delegate
        attempt.tokenTask = Task { @MainActor [weak self] in
            let token = await tokenProvider?.provideAuthToken()
            guard let self, self.activeAttempt === attempt else { return }
            guard let token else {
                self.finishAuthentication(attempt, result: .failure(.token_unavailable))
                return
            }
            guard let webView = self.webView else {
                self.finishAuthentication(attempt, result: .failure(.webview_not_created))
                return
            }
            guard let url = self.buildTokenForwardUrl(
                token: token, rtlEventId: rtlEventId, rtlRedirectUrl: rtlRedirectUrl
            ) else {
                self.finishAuthentication(attempt, result: .failure(.invalid_token_forward_url))
                return
            }
            webView.prepareAuthenticationDocument()
            attempt.awaitingWeb = true
            attempt.timeoutTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(nanoseconds: UInt64(self?.loginTimeout ?? 30) * 1_000_000_000)
                } catch { return }
                self?.finishAuthentication(attempt, result: .failure(.login_timeout))
            }
            webView.load(url: url)
        }
    }

    /// Triggers logout in the webview
    public func logout() {
        cancelAuthentication()
        webviewIsReady = false
        webView?.isHidden = true
        // An already loaded Consumer ends the server session and acknowledges logout.
        webView?.sendToWeb(.logoutRequested)
    }

    /// Route an RTL deep link received by the host app.
    ///
    /// `<scheme>://rtl-sdk/open` presents the experience. The optional
    /// `rtlRedirectUrl` takes precedence over `rtlEventId` after authentication.
    /// `<scheme>://rtl-sdk/callback` returns from an SDK-owned browser overlay.
    ///
    /// Returns true when the URL belongs to the SDK. Presentation completes
    /// asynchronously through the normal loading and readiness callbacks.
    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let route = parseRTLDeepLink(url, configuredScheme: urlScheme) else {
            return false
        }

        switch route {
        case let .open(rtlEventId, rtlRedirectUrl):
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.presentExperience(
                    rtlEventId: rtlEventId,
                    rtlRedirectUrl: rtlRedirectUrl
                )
                if !result.success, result.errorCode != RTLExperienceError.request_cancelled.rawValue {
                    RTLLog.warn(.core, "Deep-link presentation failed: \(result.errorCode ?? "unknown_error")")
                }
            }
            return true
        case let .callback(callbackURL):
            handleOverlayCallback(callbackURL)
            return true
        }
    }

    // MARK: - Location Features

    /// Enable location-based notifications
    /// Requests location and notification permissions, sets up geofencing
    public func enableLocationFeatures() {
        guard isInitialized, let baseURL = baseURL else {
            RTLLog.error(.core, "Cannot enable location features: SDK not initialized")
            return
        }

        guard !locationFeaturesEnabled else {
            RTLLog.warn(.core, "Location features already enabled")
            return
        }

        RTLLog.info(.core, "Enabling location features...")
        locationFeaturesEnabled = true

        // Initialize managers
        hyperlocalOffersService = RTLHyperlocalOffersService(
            baseURL: baseURL,
            externalChapterId: externalChapterId,
            sessionCookieHeader: { [weak self] url in
                await self?.webView?.sessionCookieHeader(for: url)
            }
        )
        notificationManager = RTLNotificationManager()
        geofenceManager = RTLGeofenceManager()
        locationManager = RTLLocationManager(sdk: self)

        // Set up location update handler
        locationManager?.onLocationUpdate = { [weak self] location in
            // Send location update to webview if it's ready
            if self?.webviewIsReady == true {
                self?.geocodeAndSendLocationUpdate(location: location)
            }
            self?.handleLocationUpdate(location)
        }

        // Set up permission change handler
        // Only send to webview if it explicitly requested permission status
        locationManager?.onPermissionChange = { [weak self] granted in
            self?.delegate?.onLocationPermissionChange?(granted: granted)

            // Send to webview if it's waiting for a permission response
            if self?.webviewAwaitingPermissionResponse == true {
                self?.webviewAwaitingPermissionResponse = false
                self?.sendLocationPermissionStatus(granted: granted)
            }
        }

        // Set up geofence enter handler
        geofenceManager?.onGeofenceEnter = { [weak self] store in
            self?.notificationManager?.showNotification(for: store)
            self?.delegate?.onGeofenceEnter?(store: store)
        }

        // Request permissions
        Task {
            await notificationManager?.requestPermission()
        }
        locationManager?.requestPermission()

        // If webview is already ready, send current permission status
        if webviewIsReady {
            let hasPermission = locationManager?.hasBackgroundPermission ?? false
            sendLocationPermissionStatus(granted: hasPermission)
        }
    }

    /// Disable location-based notifications
    public func disableLocationFeatures() {
        RTLLog.debug(.core, "Disabling location features...")
        locationManager?.stopMonitoring()
        geofenceManager?.stopMonitoring()
        locationManager = nil
        geofenceManager = nil
        hyperlocalOffersService = nil
        notificationManager = nil
        locationFeaturesEnabled = false
        webviewAwaitingPermissionResponse = false
        lastGeofenceFetchTime = nil
    }

    /// Check if location features are enabled
    var isLocationFeaturesEnabled: Bool {
        return locationFeaturesEnabled
    }

    /// Check if background location permission is granted
    public var hasLocationPermission: Bool {
        return locationManager?.hasBackgroundPermission ?? false
    }

    #if DEBUG
    /// Reset notification history for testing purposes
    /// This clears the rate limiting history to allow testing geofence notifications
    public func resetNotificationHistory() {
        notificationManager?.resetHistory()
    }
    #endif

    // MARK: - Location Handling

    private func handleLocationUpdate(_ location: CLLocation) {
        RTLLog.debug(.core, "Location update received")

        // Debounce to prevent duplicate API calls
        if let lastFetch = lastGeofenceFetchTime,
           Date().timeIntervalSince(lastFetch) < geofenceFetchDebounceInterval {
            RTLLog.warn(.core, "⏭️ Skipping duplicate location update (debounced)")
            return
        }
        lastGeofenceFetchTime = Date()

        RTLLog.debug(.core, "✅ Processing location update...")
        Task {
            await fetchAndUpdateGeofences(for: location)
        }
    }

    private func fetchAndUpdateGeofences(for location: CLLocation) async {
        guard let hyperlocalOffersService = hyperlocalOffersService else { return }

        RTLLog.debug(.core, "Fetching hyperlocal offers for the current location")

        do {
            let stores = try await hyperlocalOffersService.fetchHyperlocalOffers(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            RTLLog.debug(.core, "Fetched \(stores.count) hyperlocal offers")

            await MainActor.run {
                geofenceManager?.updateGeofences(for: stores)
            }
        } catch {
            RTLLog.error(.core, "❌ Failed to fetch hyperlocal offers: \(error)")
        }
    }

    /// Send location permission status to webview (called when permission changes)
    internal func sendLocationPermissionStatus(granted: Bool) {
        let location = locationManager?.currentLocation
        // Send immediate response first, then geocode
        sendLocationPermissionStatusImmediate(granted: granted, location: location)

        // If we have location and permission granted, also send geocoded update
        if granted, let loc = location {
            geocodeAndSendLocationUpdate(location: loc)
        }
    }

    /// Send location permission status immediately without waiting for geocoding
    private func sendLocationPermissionStatusImmediate(granted: Bool, location: CLLocation?) {
        var message: [String: Any] = ["granted": granted]

        if let loc = location {
            message["lat"] = loc.coordinate.latitude
            message["long"] = loc.coordinate.longitude
        }

        RTLLog.info(.core, "Sending location permission status")
        webView?.sendToWeb(.locationPermissionStatus, fields: message)
    }

    /// Geocode location and send locationUpdate message with full address data
    private func geocodeAndSendLocationUpdate(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                RTLLog.error(.core, "Reverse geocoding error: \(error.localizedDescription)")
            }

            var message: [String: Any] = [
                "lat": location.coordinate.latitude,
                "long": location.coordinate.longitude
            ]

            if let placemark = placemarks?.first {
                if let postalCode = placemark.postalCode {
                    message["zipCode"] = postalCode
                }
                if let city = placemark.locality {
                    message["browsingCity"] = city
                }
                if let region = placemark.administrativeArea {
                    message["browsingRegion"] = region
                }
                if let country = placemark.country {
                    message["browsingCountry"] = country
                }
            }

            RTLLog.info(.core, "Sending location update")
            self?.webView?.sendToWeb(.locationUpdate, fields: message)
        }
    }

    /// Handle location permission request from webview
    internal func handleLocationPermissionRequest() {
        RTLLog.debug(.core, "handleLocationPermissionRequest - locationFeaturesEnabled: \(locationFeaturesEnabled)")

        guard locationFeaturesEnabled else {
            sendLocationPermissionStatusImmediate(granted: false, location: nil)
            RTLLog.debug(.core, "Ignoring web permission request because the host has not enabled location features")
            return
        }

        // ALWAYS send immediate response with current status
        let hasPermission = locationManager?.hasBackgroundPermission ?? false
        let currentLocation = locationManager?.currentLocation

        RTLLog.debug(.core, "Current permission status: \(hasPermission), has location: \(currentLocation != nil)")

        // Send immediate response
        sendLocationPermissionStatusImmediate(granted: hasPermission, location: currentLocation)

        // If we have permission and location, also send geocoded update
        if hasPermission, let loc = currentLocation {
            geocodeAndSendLocationUpdate(location: loc)
        }

        // Notify the webview when a host-authorized permission request completes.
        webviewAwaitingPermissionResponse = !hasPermission
        locationManager?.requestPermission()
    }

    // MARK: - Internal Methods

    internal func handleAuthFailure() {
        if let attempt = activeAttempt, !attempt.awaitingWeb { return }
        RTLLog.error(.core, "Authentication handoff failed")
        webviewIsReady = false
        webView?.isHidden = true
        completeLogin(result: .failure(.authentication_failed))
    }

    /// Called internally when userLogout message is received
    internal func handleUserLogoutReceived() {
        cancelAuthentication()
        webView?.invalidateDocument()
        webviewIsReady = false
        webView?.isHidden = true
    }

    /// Replaces an expired web session through the host's existing token
    /// provider. The web app deliberately supplies no destination: recovery
    /// starts at the default signed-in page rather than restoring stale UI.
    @MainActor
    internal func handleSessionExpired() {
        guard webviewIsReady else {
            RTLLog.debug(.core, "Ignoring sessionExpired before the web app is ready")
            return
        }
        guard activeAttempt == nil else { return }
        startAuthentication(AuthenticationAttempt())
    }

    /// The web view has started loading the experience.
    internal func noteOpenStarted() {
        openStartedAt = Date()
    }

    /// How long this open took, from the web view starting to load until the
    /// web app said it was ready.
    ///
    /// One number, logged once per open. Everything the speed work claims is
    /// measured against it, so it is taken here rather than in a host app,
    /// where each would time it slightly differently.
    private func reportOpenDuration() {
        guard let startedAt = openStartedAt else { return }
        openStartedAt = nil

        let milliseconds = Int(Date().timeIntervalSince(startedAt) * 1000)
        RTLLog.info(.core, "Open took \(milliseconds)ms from loadStart to appReady")
    }

    internal func isCurrentWebView(_ view: RTLWebView) -> Bool { webView === view }

    private func beginAuthentication(_ attempt: AuthenticationAttempt) {
        // Register ownership before asking the host for a token. A cancelled
        // provider may still return, but can no longer navigate this WebView.
        if let previous = activeAttempt {
            finishAuthentication(previous, result: .failure(.request_cancelled), keepLoading: true)
        }
        activeAttempt = attempt
        webView?.invalidateDocument()
        webviewIsReady = false
    }

    internal func beginExampleLogin(in view: RTLWebView) {
        guard isCurrentWebView(view) else { return }
        let attempt = AuthenticationAttempt()
        attempt.awaitingWeb = true
        beginAuthentication(attempt)
        // Interactive sign-in must stay visible: appReady arrives only after
        // the user signs in. A host loader here would cover the login form.
        updateExperienceLoading(false)
        view.isHidden = false
    }

    internal func handleAppReady() {
        if let attempt = activeAttempt {
            guard attempt.awaitingWeb else { return }
        } else {
            guard webviewIsReady else { return }
        }
        reportOpenDuration()
        RTLLog.debug(.core, "Received appReady from webview")
        webviewIsReady = true
        webView?.isHidden = false
        completeLogin(result: .success)
        delegate?.onReady()

        // Send current location permission status to webview now that it's ready
        if locationFeaturesEnabled {
            let hasPermission = locationManager?.hasBackgroundPermission ?? false
            sendLocationPermissionStatus(granted: hasPermission)
        }
    }

    /// Called internally when openExternalUrl message is received
    internal func handleOpenUrl(url: URL, surface: RTLSurface) {
        let presentation: String
        switch surface {
        case .overlay:
            presentation = "SFSafariViewController"
        case .auth, .providerAuth:
            presentation = "ephemeral ASWebAuthenticationSession"
        case .external:
            presentation = "system browser"
        }
        RTLLog.info(
            .core,
            "openExternalUrl: surface=\(surface.rawValue), presentation=\(presentation), "
                + "destination=\(RTLLog.url(url.absoluteString))"
        )

        switch surface {
        case .overlay:
            guard isWebURL(url) else {
                RTLLog.error(.core, "Refused a non-web overlay URL; use the external surface for deliberate app switching")
                return
            }
            // Asked for explicitly, so no fallback: dropping to the system
            // browser would be the app-switch the caller was avoiding, and it
            // used to happen silently behind a success log.
            guard presentInAppBrowser(url: url) else {
                RTLLog.error(
                    .core,
                    "Could not present the overlay for \(url.host ?? "-"): nothing to present from"
                )
                return
            }
            RTLLog.info(.core, "Opened an in-app browser overlay for \(url.host ?? "-")")
            return
        case .auth:
            presentAuthOverlay(url: url, requireConfiguredHost: true)
            return
        case .providerAuth:
            presentAuthOverlay(url: url, requireConfiguredHost: false)
            return
        case .external:
            RTLLog.info(.core, "Opened \(url.host ?? "-") in the system browser, leaving the app")
            UIApplication.shared.open(url)
            return
        }
    }

    /// An overlay for a flow that returns a result - card linking above all.
    ///
    /// ASWebAuthenticationSession rather than a plain SFSafariViewController
    /// because it closes itself on the return redirect and hands the callback
    /// back here, matched by the system to this session rather than to
    /// whichever app claimed the scheme. That also makes it wrong for ordinary
    /// browsing, which is what `.overlay` is for: this ends only on the return
    /// redirect, and runs with an isolated cookie jar.
    ///
    /// The web decides *that* this surface is needed; the SDK decides *where*
    /// it may point, and that is our own host only. A request naming anywhere
    /// else is refused rather than downgraded: falling back to the system
    /// browser would send the user out of the app against the caller's intent,
    /// and the WebView would put the page in host-visible code.
    private func presentAuthOverlay(url: URL, requireConfiguredHost: Bool) {
        guard isWebURL(url) else {
            RTLLog.error(.core, "Refused a non-web authentication URL")
            return
        }
        if requireConfiguredHost && !isAllowedWebURL(url) {
            RTLLog.error(.core, "Refused an auth overlay for \(url.host ?? "an unknown host"): this surface is for the configured host only")
            return
        }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: urlScheme
        ) { [weak self] callbackURL, error in
            self?.overlaySession = nil
            if let callbackURL {
                if self?.handleDeepLink(callbackURL) != true {
                    RTLLog.error(.core, "Rejected an unexpected overlay callback URL")
                }
            } else if let error {
                // Cancelling is the ordinary way out, not a failure: the user
                // dismissed the sheet. The web view keeps whatever it had.
                RTLLog.info(.core, "Overlay closed without a callback: \(error.localizedDescription)")
            }
        }
        session.presentationContextProvider = overlayAnchorProvider
        // Also what removes the "Wants to Use ... to Sign In" system alert.
        // That alert exists to ask permission to share Safari's cookies, so
        // with nothing shared there is nothing to ask - and its wording would
        // be actively confusing on a card-linking flow, where the user is
        // adding a card rather than signing in anywhere.
        //
        // Correct here for its own sake too: the page authenticates from the
        // one-time token in its URL, never from a cookie carried over from
        // Safari, so an isolated jar is what this flow actually wants.
        session.prefersEphemeralWebBrowserSession = true
        overlaySession = session

        guard session.start() else {
            overlaySession = nil
            RTLLog.error(.core, "Could not start the overlay session")
            return
        }

        // Says which surface was chosen and why it was allowed, so a tester can
        // confirm isolation from the log rather than from the look of the sheet.
        RTLLog.info(
            .core,
            "Opened an isolated auth overlay (ASWebAuthenticationSession, "
                + "ephemeral) on \(url.host ?? "-")"
        )
    }

    /// Acts on the return from an overlay.
    ///
    /// The flow ends by redirecting to `<urlScheme>://rtl-sdk/callback?redirectUrl=…`,
    /// which the system matches to this session and hands back here. Without
    /// this the sheet closed and nothing else happened: the web view still held
    /// the page from before the flow, so a freshly linked card never appeared.
    ///
    /// `redirectUrl` says where in the web app to resume. Callback parameters
    /// are preserved for the reload fallback, while message-capable pages only
    /// receive the modal state they need to restore their UI.
    private func handleOverlayCallback(_ url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []

        guard
            let target = items.first(where: { $0.name == "redirectUrl" })?.value,
            var destination = URLComponents(string: target)
        else {
            RTLLog.error(.core, "Overlay returned without a usable redirectUrl")
            return
        }

        // Exclude the control params from the resumed URL, matching Android
        // and the message path below - the page should not see resume/
        // completionType echoed back into its query string.
        let carried = items.filter {
            $0.name != "redirectUrl" && $0.name != "resume" && $0.name != "completionType"
        }
        if !carried.isEmpty {
            let carriedNames = Set(carried.map(\.name))
            destination.queryItems = (destination.queryItems ?? [])
                .filter { !carriedNames.contains($0.name) } + carried
        }

        // The same host rule as opening the overlay. This URL arrives from
        // outside the app, so where it points is not taken on trust.
        guard let resumeURL = destination.url, isAllowedWebURL(resumeURL) else {
            RTLLog.error(
                .core,
                "Refused to resume at \(destination.host ?? "an unknown host"): not the configured host"
            )
            return
        }

        let resumeMode = items.first(where: { $0.name == "resume" })?.value
        let completionType = items.first(where: { $0.name == "completionType" })?.value
        if let resumeMode, resumeMode != "message" {
            RTLLog.error(.core, "Refused an overlay callback with an unknown resume mode")
            return
        }
        if resumeMode == "message", completionType?.nilIfBlank == nil {
            RTLLog.error(.core, "Refused an overlay callback without a completion type")
            return
        }

        // Consumer owns completion types and data validation. Forward new flow
        // types without an SDK upgrade, always inside the fixed envelope.
        // Cold starts use the URL fallback until the page listener is ready.
        if webviewIsReady, resumeMode == "message", let completionType {
            var data: [String: String] = [:]
            for item in destination.queryItems ?? [] where data[item.name] == nil {
                data[item.name] = item.value ?? ""
            }
            webView?.sendToWeb(.overlayCompleted, fields: [
                "completionType": completionType,
                "data": data
            ])
            return
        }

        // Says which branch was taken and why. The marker went missing once
        // already, silently, and the only symptom was a page that reloaded.
        RTLLog.info(
            .core,
            "Overlay returned; reloading the web app at \(resumeURL.path) "
                + "(resume=\(resumeMode ?? "absent"))"
        )
        webView?.load(url: resumeURL)
    }

    /// Present an in-app browser using SFSafariViewController
    /// Returns false when there was nothing to present from, so the caller can
    /// decide what that means rather than having a fallback chosen for it.
    @discardableResult
    private func presentInAppBrowser(url: URL) -> Bool {
        guard let topVC = getTopViewController() else {
            return false
        }

        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet
        topVC.present(safariVC, animated: true)
        return true
    }

    /// Get the topmost view controller for presenting modals
    private func getTopViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              let window = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootVC = window.rootViewController else {
            return nil
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    // MARK: - Private Methods

    /// Emits only loading transitions; overlapping attempts keep the loader visible.
    private func updateExperienceLoading(_ isLoading: Bool) {
        guard isExperienceLoading != isLoading else {
            if isLoading { webView?.isHidden = true }
            return
        }

        isExperienceLoading = isLoading
        delegate?.onLoadingStateChanged(isLoading: isLoading)
        if isLoading { webView?.isHidden = true }
    }

    private func cancelAuthentication() {
        if let attempt = activeAttempt {
            finishAuthentication(attempt, result: .failure(.request_cancelled))
        }
    }

    private func completeLogin(result: RTLExperienceResult) {
        if let attempt = activeAttempt {
            finishAuthentication(attempt, result: result)
        } else {
            // Readiness may also follow a reload of the current session.
            updateExperienceLoading(false)
        }
    }

    private func finishAuthentication(
        _ attempt: AuthenticationAttempt,
        result: RTLExperienceResult,
        keepLoading: Bool = false
    ) {
        guard activeAttempt === attempt else { return }
        activeAttempt = nil
        if !result.success {
            webviewIsReady = false
            webView?.isHidden = true
            webView?.invalidateDocument()
        }
        attempt.tokenTask?.cancel()
        attempt.timeoutTask?.cancel()
        let continuation = attempt.continuation
        attempt.continuation = nil
        if !keepLoading { updateExperienceLoading(false) }
        continuation?.resume(returning: result)
    }

    private func buildTokenForwardUrl(
        token: String,
        rtlEventId: String?,
        rtlRedirectUrl: String?
    ) -> URL? {
        guard let baseURL = baseURL, let urlScheme = urlScheme,
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              components.host != nil else {
            return nil
        }

        var fragmentComponents = URLComponents()
        fragmentComponents.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "appScheme", value: urlScheme)
        ]

        if let rtlEventId, !rtlEventId.isEmpty {
            fragmentComponents.queryItems?.append(URLQueryItem(name: "rtlEventId", value: rtlEventId))
        }

        if let rtlRedirectUrl, !rtlRedirectUrl.isEmpty {
            fragmentComponents.queryItems?.append(URLQueryItem(name: "rtlRedirectUrl", value: rtlRedirectUrl))
        }

        guard let fragment = fragmentComponents.percentEncodedQuery else {
            return nil
        }

        components.path = "/auth/token-forward/handoff"
        components.query = nil
        components.percentEncodedFragment = fragment
        return components.url
    }

    internal func isAllowedWebURL(_ url: URL) -> Bool {
        guard let baseURL,
              let configuredScheme = baseURL.scheme?.lowercased(),
              let candidateScheme = url.scheme?.lowercased(),
              let configuredHost = baseURL.host?.lowercased(),
              let candidateHost = url.host?.lowercased() else {
            return false
        }

        return configuredScheme == candidateScheme &&
            configuredHost == candidateHost &&
            effectivePort(for: baseURL) == effectivePort(for: url)
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private func effectivePort(for url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

}

private extension RTLExperienceResult {
    static let success = RTLExperienceResult(success: true)

    static func failure(_ error: RTLExperienceError) -> RTLExperienceResult {
        RTLExperienceResult(success: false, errorCode: error.rawValue)
    }
}

// MARK: - Overlay presentation

/// Supplies the window the overlay is anchored to.
///
/// A separate object because the protocol inherits NSObjectProtocol, and
/// making the public singleton an NSObject subclass to satisfy it would be a
/// far larger change than this needs.
private final class RTLOverlayAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows.first { $0.isKeyWindow }
            ?? ASPresentationAnchor()
    }
}
