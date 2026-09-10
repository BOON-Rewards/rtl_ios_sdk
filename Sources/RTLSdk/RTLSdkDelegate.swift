import Foundation

/// Delegate protocol for receiving RTL SDK events
@objc public protocol RTLSdkDelegate: AnyObject {

    /// Called when the RTL experience starts or stops loading.
    ///
    /// The SDK sends `true` before requesting authentication and `false` when
    /// the web app is ready or the attempt ends. Hosts can use this callback
    /// for both the initial presentation and later session recovery. It is
    /// always called on the main thread.
    func onLoadingStateChanged(isLoading: Bool)

    /// Called when the RTL web app has finished loading and is ready
    func onReady()

    /// Provides a freshly signed JWT when the SDK establishes or renews authentication.
    /// The host should fetch it from its backend and must not sign it in the app.
    /// - Returns: JWT token string, or nil if unavailable
    func provideAuthToken() async -> String?
}

// MARK: - Default Implementations

public extension RTLSdkDelegate {
    func onLoadingStateChanged(isLoading: Bool) {}
    func onReady() {}
}
