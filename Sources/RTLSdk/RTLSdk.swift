import Foundation
import UIKit
import WebKit
import CoreLocation
import SafariServices

/// Main SDK singleton for RTL webview integration
public final class RTLSdk {

    /// Shared singleton instance
    public static let shared = RTLSdk()

    // MARK: - Configuration

    private var program: String?
    private var environment: RTLEnvironment?
    private var urlScheme: String?
    private var externalChapterId: String?
    private var isInitialized = false

    // MARK: - State

    private var _isLoggedIn: Bool?
    private weak var webView: RTLWebView?

    // MARK: - Location Services

    private var locationManager: RTLLocationManager?
    private var geofenceManager: RTLGeofenceManager?
    private var storeService: RTLStoreService?
    private var notificationManager: RTLNotificationManager?
    private var locationFeaturesEnabled = false
    private var webviewAwaitingPermissionResponse = false
    private var webviewIsReady = false
    private var lastGeofenceFetchTime: Date?
    private let geofenceFetchDebounceInterval: TimeInterval = 5.0

    // MARK: - Async Login

    private var loginContinuation: CheckedContinuation<Bool, Never>?
    private var loginTimeoutTask: Task<Void, Never>?
    private let loginTimeout: TimeInterval = 30.0

    // MARK: - Token Management

    private let tokenTimestampKey = "RTLSdk.lastTokenTimestamp"
    private let tokenExpiryInterval: TimeInterval = 20 * 60 * 60 // 20 hours

    private var lastTokenTimestamp: Date? {
        get { UserDefaults.standard.object(forKey: tokenTimestampKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: tokenTimestampKey) }
    }

    private var isTokenExpired: Bool {
        guard let lastTime = lastTokenTimestamp else { return true }
        return Date().timeIntervalSince(lastTime) >= tokenExpiryInterval
    }

    // MARK: - Delegate

    /// Delegate for receiving SDK events
    public weak var delegate: RTLSdkDelegate?

    // MARK: - Initialization

    private init() {}

    /// Initialize the SDK with configuration
    /// - Parameters:
    ///   - program: The program identifier (e.g., "crowdplay")
    ///   - environment: The target environment (.staging or .production)
    ///   - urlScheme: The app's URL scheme for deep linking
    ///   - externalChapterId: The external chapter ID for location-based features (optional)
    public func initialize(program: String, environment: RTLEnvironment, urlScheme: String, externalChapterId: String? = nil) {
        self.program = program
        self.environment = environment
        self.urlScheme = urlScheme
        self.externalChapterId = externalChapterId
        self.isInitialized = true
        self._isLoggedIn = false
        setupForegroundObserver()
    }

    // MARK: - Public API

    /// Returns the current login state
    /// - Returns: `true` if logged in, `false` if not logged in, `nil` if SDK not initialized
    public func isLoggedIn() -> Bool? {
        guard isInitialized else { return nil }
        return _isLoggedIn
    }

    /// Creates an embeddable webview for the RTL experience
    /// - Returns: RTLWebView instance that can be added to your view hierarchy
    public func createWebView() -> RTLWebView {
        guard isInitialized else {
            fatalError("RTLSdk not initialized. Call initialize() first.")
        }
        let webView = RTLWebView(sdk: self)
        self.webView = webView

        // Pre-warm the webview to avoid cold-start delay (4-10 seconds)
        // This initializes WKWebView's GPU, WebContent, and Networking processes
        webView.prewarm()

        return webView
    }

    /// Request token from delegate and perform login
    /// Called on initial webview show and when token expires
    @MainActor
    public func requestTokenAndLogin() async -> Bool {
        guard let token = await delegate?.onNeedsToken() else {
            print("[RTLSdk] Token requested but delegate returned nil")
            return false
        }
        return await login(token: token)
    }

    /// Async login that completes when userAuth message is received or times out
    /// - Parameter token: JWT token from host app's auth system
    /// - Returns: `true` if login succeeded (userAuth received), `false` if failed/timed out
    @MainActor
    public func login(token: String) async -> Bool {
        guard let webView = webView else {
            print("[RTLSdk] Error: WebView not created. Call createWebView() first.")
            return false
        }

        // Cancel any existing login attempt
        cancelPendingLogin()

        let url = buildTokenForwardUrl(token: token)
        guard let url = url else {
            print("[RTLSdk] Error: Failed to build token forward URL")
            return false
        }

        webView.load(url: url)

        return await withCheckedContinuation { continuation in
            self.loginContinuation = continuation

            // Set up timeout
            self.loginTimeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(loginTimeout * 1_000_000_000))
                if !Task.isCancelled {
                    await MainActor.run {
                        self.completeLogin(success: false)
                    }
                }
            }
        }
    }

    /// Triggers logout in the webview
    public func logout() {
        let script = "window.rtlNative?.logout()"
        webView?.evaluateJavaScript(script)
    }

    // MARK: - Location Features

    /// Enable location-based notifications
    /// Requests location and notification permissions, sets up geofencing
    public func enableLocationFeatures() {
        guard isInitialized, let program = program, let environment = environment else {
            print("[RTLSdk] Cannot enable location features: SDK not initialized")
            return
        }

        guard !locationFeaturesEnabled else {
            print("[RTLSdk] Location features already enabled")
            return
        }

        print("[RTLSdk] Enabling location features...")
        locationFeaturesEnabled = true

        // Initialize managers
        storeService = RTLStoreService(program: program, environment: environment, externalChapterId: externalChapterId)
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
        print("[RTLSdk] Disabling location features...")
        locationManager?.stopMonitoring()
        geofenceManager?.stopMonitoring()
        locationFeaturesEnabled = false
    }

    /// Check if location features are enabled
    public var isLocationFeaturesEnabled: Bool {
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
        print("[RTLSdk] 📍 Location update received: (\(location.coordinate.latitude), \(location.coordinate.longitude))")

        // Debounce to prevent duplicate API calls
        if let lastFetch = lastGeofenceFetchTime,
           Date().timeIntervalSince(lastFetch) < geofenceFetchDebounceInterval {
            print("[RTLSdk] ⏭️ Skipping duplicate location update (debounced)")
            return
        }
        lastGeofenceFetchTime = Date()

        print("[RTLSdk] ✅ Processing location update...")
        Task {
            await fetchAndUpdateGeofences(for: location)
        }
    }

    private func fetchAndUpdateGeofences(for location: CLLocation) async {
        guard let storeService = storeService else { return }

        print("[RTLSdk] 📍 Fetching stores for location: (\(location.coordinate.latitude), \(location.coordinate.longitude))")

        do {
            let stores = try await storeService.fetchNearbyStores(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )

            print("[RTLSdk] 🏪 Fetched \(stores.count) stores:")
            for store in stores {
                print("[RTLSdk]   - \(store.name) @ (\(store.latitude), \(store.longitude))")
            }

            await MainActor.run {
                geofenceManager?.updateGeofences(for: stores)
            }
        } catch {
            print("[RTLSdk] ❌ Failed to fetch nearby stores: \(error)")
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
        var message: [String: Any] = [
            "type": "locationPermissionStatus",
            "granted": granted
        ]

        if let loc = location {
            message["lat"] = loc.coordinate.latitude
            message["long"] = loc.coordinate.longitude
        }

        print("[RTLSdk] Sending immediate location permission status: \(message)")
        webView?.postMessage(message)
    }

    /// Geocode location and send locationUpdate message with full address data
    private func geocodeAndSendLocationUpdate(location: CLLocation) {
        let geocoder = CLGeocoder()
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error = error {
                print("[RTLSdk] Reverse geocoding error: \(error.localizedDescription)")
            }

            var message: [String: Any] = [
                "type": "locationUpdate",
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

            print("[RTLSdk] Sending location update: \(message)")
            self?.webView?.postMessage(message)
        }
    }

    /// Handle location permission request from webview
    internal func handleLocationPermissionRequest() {
        print("[RTLSdk] handleLocationPermissionRequest - locationFeaturesEnabled: \(locationFeaturesEnabled)")

        // ALWAYS send immediate response with current status
        let hasPermission = locationManager?.hasBackgroundPermission ?? false
        let currentLocation = locationManager?.currentLocation

        print("[RTLSdk] Current permission status: \(hasPermission), has location: \(currentLocation != nil)")

        // Send immediate response
        sendLocationPermissionStatusImmediate(granted: hasPermission, location: currentLocation)

        // If we have permission and location, also send geocoded update
        if hasPermission, let loc = currentLocation {
            geocodeAndSendLocationUpdate(location: loc)
        }

        // If permission not granted, mark that webview is waiting for response
        // so we can notify it when permission changes
        if !hasPermission {
            webviewAwaitingPermissionResponse = true
        }

        // Now handle requesting permission if needed
        if locationFeaturesEnabled {
            locationManager?.requestPermission()
        } else {
            // Auto-enable location features when requested by web
            print("[RTLSdk] Location features not enabled, enabling now...")
            enableLocationFeatures()
        }
    }

    // MARK: - Internal Methods

    /// Called internally when userAuth message is received from webview
    internal func handleUserAuthReceived(accessToken: String, refreshToken: String) {
        _isLoggedIn = true
        lastTokenTimestamp = Date()
        delegate?.onAuthenticated(accessToken: accessToken, refreshToken: refreshToken)
        completeLogin(success: true)
    }

    /// Called internally when userLogout message is received
    internal func handleUserLogoutReceived() {
        _isLoggedIn = false
        delegate?.onLogout()
    }

    /// Called internally when appReady message is received
    internal func handleAppReady() {
        print("[RTLSdk] Received appReady from webview")
        webviewIsReady = true
        delegate?.onReady()

        // Send current location permission status to webview now that it's ready
        if locationFeaturesEnabled {
            let hasPermission = locationManager?.hasBackgroundPermission ?? false
            sendLocationPermissionStatus(granted: hasPermission)
        }
    }

    /// Called internally when openExternalUrl message is received
    internal func handleOpenUrl(url: URL, forceExternal: Bool) {
        if forceExternal {
            // Open in external browser (Safari)
            UIApplication.shared.open(url)
        } else {
            // Open in-app browser (SFSafariViewController)
            presentInAppBrowser(url: url)
        }
        // Notify delegate (informational - no action required)
        delegate?.onOpenUrl(url: url, forceExternal: forceExternal)
    }

    /// Present an in-app browser using SFSafariViewController
    private func presentInAppBrowser(url: URL) {
        guard let topVC = getTopViewController() else {
            print("[RTLSdk] Cannot present in-app browser: no top view controller, falling back to Safari")
            // Fallback to external browser
            UIApplication.shared.open(url)
            return
        }

        let safariVC = SFSafariViewController(url: url)
        safariVC.modalPresentationStyle = .pageSheet
        topVC.present(safariVC, animated: true)
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

    private func cancelPendingLogin() {
        loginTimeoutTask?.cancel()
        loginTimeoutTask = nil
        loginContinuation?.resume(returning: false)
        loginContinuation = nil
    }

    private func completeLogin(success: Bool) {
        loginTimeoutTask?.cancel()
        loginTimeoutTask = nil
        loginContinuation?.resume(returning: success)
        loginContinuation = nil
    }

    private func buildTokenForwardUrl(token: String) -> URL? {
        guard let program = program, let environment = environment, let urlScheme = urlScheme else {
            return nil
        }

        let domain: String
        switch environment {
        case .staging:
            domain = "\(program).staging.getboon.com"
        case .production:
            domain = "\(program).prod.getboon.com"
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = domain
        components.path = "/auth/token-forward"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "isWrappedMobileApp", value: "true"),
            URLQueryItem(name: "embeddedProgramId", value: program),
            URLQueryItem(name: "appScheme", value: urlScheme)
        ]

        return components.url
    }

    // MARK: - Configuration Accessors (Internal)

    internal var currentProgram: String? { program }
    internal var currentEnvironment: RTLEnvironment? { environment }

    // MARK: - App Lifecycle

    private func setupForegroundObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func appWillEnterForeground() {
        Task { @MainActor in
            await checkAndRefreshTokenIfNeeded()
        }
    }

    @MainActor
    private func checkAndRefreshTokenIfNeeded() async {
        guard isTokenExpired else {
            print("[RTLSdk] Token still valid, no refresh needed")
            return
        }
        guard webView != nil else {
            print("[RTLSdk] WebView not created, skipping token refresh")
            return
        }
        print("[RTLSdk] Token expired, requesting fresh token...")
        _ = await requestTokenAndLogin()
    }
}
