import Foundation

/// Delegate protocol for receiving RTL SDK events
@objc public protocol RTLSdkDelegate: AnyObject {

    /// Called when user authentication succeeds
    /// - Parameters:
    ///   - accessToken: The access token from authentication
    ///   - refreshToken: The refresh token from authentication
    func onAuthenticated(accessToken: String, refreshToken: String)

    /// Called when user logs out
    func onLogout()

    /// Called when the RTL web app opens a URL (informational)
    /// URLs are handled automatically by the SDK
    /// - Parameters:
    ///   - url: The URL that was opened
    ///   - forceExternal: If true, opened in external browser; otherwise in-app browser
    func onOpenUrl(url: URL, forceExternal: Bool)

    /// Called when the RTL web app has finished loading and is ready
    func onReady()

    /// Called when SDK needs a fresh token from the host app
    /// This is called on initial webview load and when token expires after 20 hours
    /// - Returns: JWT token string, or nil if unavailable
    func onNeedsToken() async -> String?

    // MARK: - Location Callbacks (Optional)

    /// Called when location permission status changes
    /// - Parameter granted: true if background location permission is granted
    @objc optional func onLocationPermissionChange(granted: Bool)

    /// Called when user enters a store geofence
    /// - Parameter store: The store that was entered
    @objc optional func onGeofenceEnter(store: RTLStore)
}

// MARK: - Default Implementations

public extension RTLSdkDelegate {

    func onAuthenticated(accessToken: String, refreshToken: String) {}

    func onLogout() {}

    func onOpenUrl(url: URL, forceExternal: Bool) {}

    func onReady() {}

    func onNeedsToken() async -> String? { nil }
}
