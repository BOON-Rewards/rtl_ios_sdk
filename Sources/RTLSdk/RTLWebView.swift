import UIKit
import WebKit

// The authentication state machine only needs these operations. Keeping this
// boundary internal lets lifecycle tests use a view without WebKit processes.
protocol RTLExperienceView: AnyObject {
    var isHidden: Bool { get set }
    func prepareAuthenticationDocument()
    func invalidateDocument()
    func load(url: URL)
    func sendToWeb(_ type: RTLNativeMessageType, fields: [String: Any])
    func sessionCookieHeader(for url: URL) async -> String?
}

extension RTLWebView: RTLExperienceView {}

/// Embeddable webview for RTL experience
public class RTLWebView: UIView {

    // MARK: - Properties

    private var webView: WKWebView
    private weak var sdk: RTLSdk?
    private var bridge: RTLBridge
    private let hapticEngine: RTLHapticEngine
    private var backgroundObserver: NSObjectProtocol?
    private var authenticationChallengeHandler: RTLAuthenticationChallengeHandler?
    private var onAuthenticationChallengeFailure: (() -> Void)?

    @_spi(RTLExample)
    public func setAuthenticationChallengeHandlerForExample(
        _ handler: RTLAuthenticationChallengeHandler?,
        onFailure: (() -> Void)? = nil
    ) {
        authenticationChallengeHandler = handler
        onAuthenticationChallengeFailure = onFailure
        // Keep the current document alive so it can finish server logout.
        // Both token-forward and example login prepare a fresh document before
        // navigation, applying the updated handler's data-store configuration.
    }

    public override var isHidden: Bool {
        didSet {
            if isHidden {
                hapticEngine.stop()
            }
        }
    }

    // MARK: - Initialization

    #if DEBUG
    private static let consoleLogHandler = "rtlConsoleLog"
    #endif

    init(sdk: RTLSdk) {
        self.sdk = sdk
        let hapticEngine = RTLHapticEngine()
        self.hapticEngine = hapticEngine
        self.bridge = RTLBridge(sdk: sdk, hapticEngine: hapticEngine)

        self.webView = WKWebView(frame: .zero, configuration: Self.configuration(bridge: bridge))

        super.init(frame: .zero)

        bridge.attach(to: webView, owner: self)
        setupWebView()
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hapticEngine.stop()
        }
    }

    private static func configuration(bridge: RTLBridge, ephemeral: Bool = false) -> WKWebViewConfiguration {
        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        if ephemeral {
            configuration.websiteDataStore = .nonPersistent()
        }
        let contentController = WKUserContentController()

        // Add message handler for JavaScript bridge
        contentController.add(bridge, name: RTLBridge.name)

        // Page console output can contain credentials or personal data. Keep
        // this native debugging aid out of production SDK builds.
        #if DEBUG
        let consoleLogScript = WKUserScript(
            source: RTLWebView.consoleLogOverrideScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(consoleLogScript)
        contentController.add(ConsoleLogHandler(), name: RTLWebView.consoleLogHandler)
        #endif

        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        return configuration
    }

    #if DEBUG
    private static var consoleLogOverrideScript: String {
        """
        (function() {
            var originalLog = console.log;
            var originalWarn = console.warn;
            var originalError = console.error;
            var originalInfo = console.info;

            function postToNative(level, args) {
                var message = Array.prototype.slice.call(args).map(function(arg) {
                    if (typeof arg === 'object') {
                        try { return JSON.stringify(arg); } catch(e) { return String(arg); }
                    }
                    return String(arg);
                }).join(' ');
                window.webkit.messageHandlers.rtlConsoleLog.postMessage({level: level, message: message});
            }

            console.log = function() { postToNative('LOG', arguments); originalLog.apply(console, arguments); };
            console.warn = function() { postToNative('WARN', arguments); originalWarn.apply(console, arguments); };
            console.error = function() { postToNative('ERROR', arguments); originalError.apply(console, arguments); };
            console.info = function() { postToNative('INFO', arguments); originalInfo.apply(console, arguments); };
        })();
        """
    }
    #endif

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use RTLSdk.shared.createWebView() instead.")
    }

    deinit {
        hapticEngine.stop()
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
        }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RTLBridge.name)
        #if DEBUG
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RTLWebView.consoleLogHandler)
        #endif
    }

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            hapticEngine.stop()
        }
    }

    // MARK: - Setup

    private func setupWebView() {
        clipsToBounds = true
        // Let the host's backing color show instead of WebKit's default white
        // while the document loads. The page controls its own scroll-bounce color.
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = true
        webView.scrollView.alwaysBounceVertical = true
        // Each authentication document gets a new WKWebView. Keep its refresh
        // control local to that scroll view instead of moving one between views.
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        refreshControl.accessibilityLabel = "Refresh"
        refreshControl.tintColor = UIColor(white: 0.93, alpha: 1.0)
        webView.scrollView.refreshControl = refreshControl

        // Enable inspection in debug builds
        #if DEBUG
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
        }
        #endif

        addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    // MARK: - SDK Methods

    @objc private func handlePullToRefresh() {
        guard let currentURL = webView.url,
              currentURL.absoluteString != "about:blank" else {
            finishPullToRefresh()
            return
        }

        webView.reload()
    }

    private func finishPullToRefresh() {
        webView.scrollView.refreshControl?.endRefreshing()
    }

    /// Retire the old document and its queued messages without changing the host view.
    func invalidateDocument() {
        finishPullToRefresh()
        bridge.invalidate()
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        webView.isHidden = true
        hapticEngine.stop()
    }

    func prepareAuthenticationDocument() {
        guard let sdk else { return }
        invalidateDocument()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        bridge = RTLBridge(sdk: sdk, hapticEngine: hapticEngine)
        webView = WKWebView(frame: .zero, configuration: Self.configuration(
            bridge: bridge, ephemeral: authenticationChallengeHandler != nil
        ))
        bridge.attach(to: webView, owner: self)
        setupWebView()
    }

    /// Load a URL in the webview
    /// - Parameter url: The URL to load
    func load(url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    /// Loads the unauthenticated sign-in page used by the bundled SDK examples.
    /// Host integrations should use `RTLSdk.presentExperience(...)`.
    @_spi(RTLExample)
    public func loadLoginForExample(url: URL) {
        sdk?.beginExampleLogin(in: self)
        prepareAuthenticationDocument()
        load(url: url)
    }

    /// Returns the signed-in WebView session in HTTP header form for an SDK
    /// request to the same host. The cookie stays inside native SDK networking;
    /// it is never sent through the JavaScript bridge or exposed to the host.
    func sessionCookieHeader(for url: URL) async -> String? {
        let cookies = await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
                continuation.resume(returning: $0)
            }
        }
        let matching = cookies.filter {
            $0.name == "token" && Self.cookie($0, appliesTo: url)
        }
        return HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
    }

    private static func cookie(_ cookie: HTTPCookie, appliesTo url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let domain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = host == domain || host.hasSuffix(".\(domain)")
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        let pathMatches = url.path.isEmpty || url.path.hasPrefix(cookiePath)
        let secureMatches = !cookie.isSecure || url.scheme?.lowercased() == "https"
        return domainMatches && pathMatches && secureMatches
    }

    /// Reload the current page
    func reload() {
        webView.reload()
    }

    /// Go back in history
    func goBack() {
        webView.goBack()
    }

    /// Go forward in history
    func goForward() {
        webView.goForward()
    }

    /// Check if can go back
    var canGoBack: Bool {
        webView.canGoBack
    }

    /// Check if can go forward
    var canGoForward: Bool {
        webView.canGoForward
    }

    func sendToWeb(_ type: RTLNativeMessageType, fields: [String: Any] = [:]) {
        bridge.sendToWeb(type, fields: fields)
    }
}

// MARK: - WKNavigationDelegate

extension RTLWebView: WKNavigationDelegate {

    public func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard webView === self.webView else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        guard let handler = authenticationChallengeHandler else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        let (disposition, credential) = handler.response(to: challenge)
        completionHandler(disposition, credential)
        if disposition == .cancelAuthenticationChallenge {
            onAuthenticationChallengeFailure?()
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        let urlString = url.absoluteString

        // Allow about:blank
        if urlString == "about:blank" {
            decisionHandler(.allow)
            return
        }

        if sdk?.isAllowedWebURL(url) == true {
            decisionHandler(.allow)
            return
        }

        // Anything off our host is refused here and opened in the overlay
        // instead. This web view holds the session cookie, so a third-party
        // page has no business loading in it - and the overlay is browser-owned
        // and unreadable by this app, which is where such a page belongs.
        //
        // This is also how flows that navigate on their own terms are caught.
        // Open banking's providers redirect the page rather than asking the
        // bridge to open anything, so there is nothing to intercept except the
        // navigation itself.
        RTLLog.info(.webView, "Navigation to \(url.host ?? "another host") captured into the overlay")
        sdk?.handleOpenUrl(url: url, surface: .overlay)
        decisionHandler(.cancel)
    }

    public func webView(
        _ webView: WKWebView,
        didStartProvisionalNavigation navigation: WKNavigation!
    ) {
        // The clock starts here rather than at load(url:), so it measures what
        // the user waits for rather than how promptly we asked. A nil or blank
        // URL is not a real open, so it is skipped (Android does the same).
        if let current = webView.url?.absoluteString, current != "about:blank" {
            sdk?.noteOpenStarted()
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishPullToRefresh()
        RTLLog.debug(.webView, "WebView finished loading: \(RTLLog.url(webView.url?.absoluteString ?? "unknown"))")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishPullToRefresh()
        RTLLog.error(.webView, "WebView navigation failed: \(error.localizedDescription)")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishPullToRefresh()
        RTLLog.error(.webView, "WebView provisional navigation failed: \(error.localizedDescription)")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishPullToRefresh()
        hapticEngine.stop()
        RTLLog.debug(.webView, "WebView content process terminated")
    }
}

extension RTLWebView: WKUIDelegate {
    /// `window.open` from the page.
    ///
    /// WKWebView drops these unless a UI delegate handles them, so a provider
    /// SDK that opens a popup rather than navigating did nothing at all and
    /// gave no clue why. Returning nil keeps the popup from being created; the
    /// destination goes to the overlay instead, the same as a navigation.
    public func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            RTLLog.info(.webView, "window.open for \(url.host ?? "an unknown host") captured into the overlay")
            sdk?.handleOpenUrl(url: url, surface: .overlay)
        }
        return nil
    }
}

// MARK: - Console Log Handler

#if DEBUG
private class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let level = body["level"] as? String,
              let logMessage = body["message"] as? String else {
            return
        }
        // The page's own console level carries through, so a JS error reads as
        // an error rather than being flattened into our debug stream.
        switch level.lowercased() {
        case "error":
            RTLLog.error(.webView, logMessage)
        case "warn", "warning":
            RTLLog.warn(.webView, logMessage)
        case "info":
            RTLLog.info(.webView, logMessage)
        default:
            RTLLog.debug(.webView, logMessage)
        }
    }
}
#endif
