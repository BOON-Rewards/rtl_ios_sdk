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
}

// MARK: - Default Implementations

public extension RTLSdkDelegate {

    func rtlSdkDidAuthenticate(accessToken: String, refreshToken: String) {}

    func rtlSdkDidLogout() {}

    func rtlSdkRequestsOpenUrl(url: URL, forceExternal: Bool) {}

    func rtlSdkDidBecomeReady() {}
}
