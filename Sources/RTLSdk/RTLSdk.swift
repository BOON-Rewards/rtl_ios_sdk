import Foundation
import WebKit

/// Main SDK singleton for RTL webview integration
public final class RTLSdk {

    /// Shared singleton instance
    public static let shared = RTLSdk()

    // MARK: - Configuration

    private var program: String?
    private var environment: RTLEnvironment?
    private var urlScheme: String?
    private var isInitialized = false

    // MARK: - State

    private var _isLoggedIn: Bool?
    private weak var webView: RTLWebView?

    // MARK: - Async Login

    private var loginContinuation: CheckedContinuation<Bool, Never>?
    private var loginTimeoutTask: Task<Void, Never>?
    private let loginTimeout: TimeInterval = 30.0

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
    public func initialize(program: String, environment: RTLEnvironment, urlScheme: String) {
        self.program = program
        self.environment = environment
        self.urlScheme = urlScheme
        self.isInitialized = true
        self._isLoggedIn = false
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
        return webView
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

    /// Register a push notification token with the RTL backend
    /// - Parameters:
    ///   - token: The device push token
    ///   - type: The token type (.apns or .fcm)
    public func registerPushToken(_ token: String, type: RTLTokenType) {
        let escapedToken = token.replacingOccurrences(of: "'", with: "\\'")
        let script = "window.rtlNative?.registerPushToken('\(escapedToken)', '\(type.rawValue)')"
        webView?.evaluateJavaScript(script)
    }

    // MARK: - Internal Methods

    /// Called internally when userAuth message is received from webview
    internal func handleUserAuthReceived(accessToken: String, refreshToken: String) {
        _isLoggedIn = true
        delegate?.rtlSdkDidAuthenticate(accessToken: accessToken, refreshToken: refreshToken)
        completeLogin(success: true)
    }

    /// Called internally when userLogout message is received
    internal func handleUserLogoutReceived() {
        _isLoggedIn = false
        delegate?.rtlSdkDidLogout()
    }

    /// Called internally when appReady message is received
    internal func handleAppReady() {
        delegate?.rtlSdkDidBecomeReady()
    }

    /// Called internally when openExternalUrl message is received
    internal func handleOpenUrl(url: URL, forceExternal: Bool) {
        delegate?.rtlSdkRequestsOpenUrl(url: url, forceExternal: forceExternal)
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
}
