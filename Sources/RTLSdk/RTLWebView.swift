import UIKit
import WebKit

/// Embeddable webview for RTL experience
public class RTLWebView: UIView {

    // MARK: - Properties

    private let webView: WKWebView
    private weak var sdk: RTLSdk?
    private let messageHandler: RTLMessageHandler

    // MARK: - Initialization

    init(sdk: RTLSdk) {
        self.sdk = sdk
        self.messageHandler = RTLMessageHandler()

        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Add message handler for JavaScript bridge
        contentController.add(messageHandler, name: RTLMessageHandler.handlerName)

        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)

        messageHandler.delegate = self
        setupWebView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use RTLSdk.shared.createWebView() instead.")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RTLMessageHandler.handlerName)
    }

    // MARK: - Setup

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.scrollView.bounces = true

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

    // MARK: - Public Methods

    /// Load a URL in the webview
    /// - Parameter url: The URL to load
    public func load(url: URL) {
        let request = URLRequest(url: url)
        webView.load(request)
    }

    /// Evaluate JavaScript in the webview
    /// - Parameter script: The JavaScript to evaluate
    public func evaluateJavaScript(_ script: String) {
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("[RTLSdk] JavaScript evaluation error: \(error.localizedDescription)")
            }
        }
    }

    /// Reload the current page
    public func reload() {
        webView.reload()
    }

    /// Go back in history
    public func goBack() {
        webView.goBack()
    }

    /// Go forward in history
    public func goForward() {
        webView.goForward()
    }

    /// Check if can go back
    public var canGoBack: Bool {
        webView.canGoBack
    }

    /// Check if can go forward
    public var canGoForward: Bool {
        webView.canGoForward
    }
}

// MARK: - WKNavigationDelegate

extension RTLWebView: WKNavigationDelegate {

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

        // Check for allowed domains
        let host = url.host ?? ""
        let isAllowedDomain = host.contains("getboon.com") ||
                              host.contains("affinaloyalty.com")

        if isAllowedDomain {
            decisionHandler(.allow)
        } else {
            // External URL - notify delegate
            sdk?.handleOpenUrl(url: url, forceExternal: true)
            decisionHandler(.cancel)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("[RTLSdk] WebView finished loading: \(webView.url?.absoluteString ?? "unknown")")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[RTLSdk] WebView navigation failed: \(error.localizedDescription)")
    }
}

// MARK: - RTLMessageHandlerDelegate

extension RTLWebView: RTLMessageHandlerDelegate {

    func messageHandler(_ handler: RTLMessageHandler, didReceiveUserAuth accessToken: String, refreshToken: String) {
        sdk?.handleUserAuthReceived(accessToken: accessToken, refreshToken: refreshToken)
    }

    func messageHandler(_ handler: RTLMessageHandler, didReceiveUserLogout: Void) {
        sdk?.handleUserLogoutReceived()
    }

    func messageHandler(_ handler: RTLMessageHandler, didReceiveAppReady: Void) {
        sdk?.handleAppReady()
    }

    func messageHandler(_ handler: RTLMessageHandler, didRequestOpenUrl url: URL, forceExternal: Bool) {
        sdk?.handleOpenUrl(url: url, forceExternal: forceExternal)
    }
}
