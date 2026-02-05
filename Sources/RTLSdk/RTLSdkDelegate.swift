import Foundation

/// Delegate protocol for receiving RTL SDK events
public protocol RTLSdkDelegate: AnyObject {

    /// Called when user authentication succeeds
    /// - Parameters:
    ///   - accessToken: The access token from authentication
    ///   - refreshToken: The refresh token from authentication
    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String)

    /// Called when user logs out
    func rtlSdkDidLogout()

    /// Called when the RTL web app requests opening a URL
    /// - Parameters:
    ///   - url: The URL to open
    ///   - forceExternal: If true, should open in external browser; otherwise can use in-app browser
    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool)

    /// Called when the RTL web app has finished loading and is ready
    func rtlSdkDidBecomeReady()

    /// Called when SDK needs a fresh token from the host app
    /// This is called on initial webview load and when token expires after 20 hours
    /// - Returns: JWT token string, or nil if unavailable
    func rtlSdkNeedsToken() async -> String?
}

// MARK: - Default Implementations

public extension RTLSdkDelegate {

    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {}

    func rtlSdkDidLogout() {}

    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {}

    func rtlSdkDidBecomeReady() {}

    func rtlSdkNeedsToken() async -> String? { nil }
}
