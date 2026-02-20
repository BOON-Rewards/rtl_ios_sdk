import UIKit
import WebKit

/// Embeddable webview for RTL experience
public class RTLWebView: UIView {

    // MARK: - Properties

    private let webView: WKWebView
    private weak var sdk: RTLSdk?
    private let messageHandler: RTLMessageHandler

    // MARK: - Initialization

    private static let consoleLogHandler = "rtlConsoleLog"

    init(sdk: RTLSdk) {
        self.sdk = sdk
        self.messageHandler = RTLMessageHandler()

        // Configure WKWebView
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()

        // Add message handler for JavaScript bridge
        contentController.add(messageHandler, name: RTLMessageHandler.handlerName)

        // Add console log capture script
        let consoleLogScript = WKUserScript(
            source: RTLWebView.consoleLogOverrideScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(consoleLogScript)
        contentController.add(ConsoleLogHandler(), name: RTLWebView.consoleLogHandler)

        configuration.userContentController = contentController
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        self.webView = WKWebView(frame: .zero, configuration: configuration)

        super.init(frame: .zero)

        messageHandler.delegate = self
        setupWebView()
    }

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use RTLSdk.shared.createWebView() instead.")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RTLMessageHandler.handlerName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: RTLWebView.consoleLogHandler)
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

    /// Pre-warm the webview by loading a blank page
    /// This initializes WKWebView's web processes in the background,
    /// avoiding the 4-10 second delay when the actual content is loaded
    public func prewarm() {
        print("[RTLSdk] 🔥 Pre-warming webview...")
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }

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

    /// Post a message to the web content
    /// - Parameter message: Dictionary to send as JSON via window.postMessage
    public func postMessage(_ message: [String: Any]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[RTLSdk] Failed to serialize message to JSON")
            return
        }

        print("[RTLSdk] 📤 Posting message to webview: \(jsonString)")
        let script = "window.postMessage(\(jsonString), '*')"
        evaluateJavaScript(script)
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

    func messageHandler(_ handler: RTLMessageHandler, didRequestLocationPermission: Void) {
        sdk?.handleLocationPermissionRequest()
    }
}

// MARK: - Console Log Handler

private class ConsoleLogHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let level = body["level"] as? String,
              let logMessage = body["message"] as? String else {
            return
        }
        print("[WebView \(level)] \(logMessage)")
    }
}
