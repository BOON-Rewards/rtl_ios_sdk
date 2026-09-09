import XCTest
@_spi(RTLExample) @testable import RTLSdk

@MainActor
final class RTLSdkLoadingTests: XCTestCase {
    func testTokenUnavailableEndsLoadingWithoutBecomingReady() async {
        let delegate = LoadingDelegate()
        RTLSdk.shared.initialize(
            baseURL: URL(string: "https://example.com")!,
            urlScheme: "example",
            delegate: delegate
        )

        let result = await RTLSdk.shared.presentExperience()

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.errorCode, "token_unavailable")
        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertEqual(delegate.readyCount, 0)
    }

    func testSessionRecoveryCoalescesAndSucceeds() async {
        let delegate = LoadingDelegate(token: "replacement-token")
        let sdk = RTLSdk.shared
        sdk.initialize(
            baseURL: URL(string: "https://example.com")!,
            urlScheme: "example",
            delegate: delegate
        )
        let webView = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.beginExampleLogin(in: webView)
        sdk.handleAppReady()
        delegate.reset()

        sdk.handleSessionExpired()
        sdk.handleSessionExpired()
        await delegate.waitForTokenRequest()
        await waitForHandoff(webView)
        sdk.handleAppReady()
        await Task.yield()

        XCTAssertEqual(delegate.tokenRequestCount, 1)
        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertEqual(delegate.readyCount, 1)
        XCTAssertFalse(webView.isHidden)
    }

    func testSessionRecoveryStopsLoadingWhenTokenIsUnavailable() async {
        let delegate = LoadingDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(
            baseURL: URL(string: "https://example.com")!,
            urlScheme: "example",
            delegate: delegate
        )
        let webView = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.beginExampleLogin(in: webView)
        sdk.handleAppReady()
        delegate.reset()

        sdk.handleSessionExpired()
        sdk.handleSessionExpired()
        await delegate.waitForLoadingToStop()

        XCTAssertEqual(delegate.tokenRequestCount, 1)
        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertTrue(webView.isHidden)
        XCTAssertTrue(webView.requestedURLs.isEmpty)
    }

    func testAuthenticationFailureStopsRecoveryWithoutReadiness() async {
        let delegate = LoadingDelegate(token: "rejected-token")
        let sdk = RTLSdk.shared
        sdk.initialize(
            baseURL: URL(string: "https://example.com")!,
            urlScheme: "example",
            delegate: delegate
        )
        let webView = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.beginExampleLogin(in: webView)
        sdk.handleAppReady()
        delegate.reset()

        sdk.handleSessionExpired()
        await delegate.waitForTokenRequest()
        await waitForHandoff(webView)
        sdk.handleAuthFailure()
        await Task.yield()

        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertTrue(webView.isHidden)
    }

    func testLateReadyAfterLogoutDuringHandoffStaysHiddenAndRetrySucceeds() async {
        let delegate = LoadingDelegate(token: "token")
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        let presentation = Task { await sdk.presentExperience() }
        await waitForHandoff(view)
        sdk.logout()
        let cancelled = await presentation.value
        XCTAssertEqual(cancelled.errorCode, "request_cancelled")
        sdk.handleAppReady()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(delegate.readyCount, 0)

        let retryView = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        let retry = Task { await sdk.presentExperience() }
        await waitForHandoff(retryView)
        sdk.handleAppReady()
        let result = await retry.value
        XCTAssertTrue(result.success)
        XCTAssertFalse(retryView.isHidden)
        XCTAssertEqual(delegate.readyCount, 1)
    }

    func testLateReadyAfterCallerCancellationIsIgnored() async {
        let delegate = LoadingDelegate(token: "token")
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        let presentation = Task { await sdk.presentExperience() }
        await waitForHandoff(view)
        presentation.cancel()
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "request_cancelled")
        XCTAssertEqual(delegate.loadingStates, [true, false])
        sdk.handleAppReady()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(delegate.readyCount, 0)
    }

    func testLateReadyAfterTimeoutIsIgnored() async {
        let delegate = LoadingDelegate(token: "token")
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        let presentation = Task { await sdk.presentExperience() }
        await waitForHandoff(view)
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "login_timeout")
        sdk.handleAppReady()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(delegate.readyCount, 0)
    }

    func testExampleLoginShowsSignInWithoutWaitingForReadiness() {
        let delegate = LoadingDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.handleAppReady()
        XCTAssertEqual(delegate.readyCount, 0)
        let loginURL = URL(string: "https://example.com")!
        view.loadLoginForExample(url: loginURL)
        XCTAssertEqual(view.requestedURLs, [loginURL])
        XCTAssertFalse(view.isHidden)
        XCTAssertTrue(delegate.loadingStates.isEmpty)
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertEqual(delegate.tokenRequestCount, 0)
        sdk.handleAppReady()
        XCTAssertEqual(delegate.readyCount, 1)
        XCTAssertTrue(delegate.loadingStates.isEmpty)
        XCTAssertEqual(delegate.tokenRequestCount, 0)
        sdk.logout()
        sdk.handleAppReady()
        XCTAssertTrue(view.isHidden)
        XCTAssertEqual(delegate.readyCount, 1)
    }

    func testLogoutDuringInternalLoginHidesSignInAndRejectsLateReadiness() {
        let delegate = LoadingDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.beginExampleLogin(in: view)
        sdk.logout()
        sdk.handleAppReady()
        XCTAssertTrue(delegate.loadingStates.isEmpty)
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertTrue(view.isHidden)
    }

    func testInternalLoginFailureEndsAttemptAndAllowsRetry() {
        let delegate = LoadingDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        sdk.beginExampleLogin(in: view)
        sdk.handleAuthFailure()
        sdk.handleAppReady()
        XCTAssertTrue(delegate.loadingStates.isEmpty)
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertTrue(view.isHidden)

        sdk.beginExampleLogin(in: view)
        XCTAssertFalse(view.isHidden)
        sdk.handleAppReady()
        XCTAssertTrue(delegate.loadingStates.isEmpty)
        XCTAssertEqual(delegate.readyCount, 1)
        XCTAssertFalse(view.isHidden)
    }

    func testSwitchingToExampleLoginDismissesPendingTokenLoader() async {
        let delegate = LoadingDelegate(token: "token")
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let view = sdk.createWebView(using: { RecordingWebView(sdk: $0) })
        let presentation = Task { await sdk.presentExperience() }
        await waitForHandoff(view)
        XCTAssertEqual(delegate.loadingStates, [true])
        XCTAssertTrue(view.isHidden)

        sdk.beginExampleLogin(in: view)
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "request_cancelled")
        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertFalse(view.isHidden)
        XCTAssertEqual(delegate.readyCount, 0)
        sdk.handleAppReady()
        XCTAssertEqual(delegate.readyCount, 1)
        XCTAssertFalse(view.isHidden)
    }

    private func waitForHandoff(_ view: RecordingWebView) async {
        await fulfillment(of: [view.handoffRequested], timeout: 3)
        XCTAssertEqual(view.requestedURLs.count, 1)
        XCTAssertEqual(view.requestedURLs.first?.path, "/auth/token-forward/handoff")
    }

    func testNewPresentationOwnsLateTokenResponses() async {
        let delegate = DelayedDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let first = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(1)
        let second = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(2)
        let cancelled = await first.value
        XCTAssertEqual(cancelled.errorCode, "request_cancelled")
        delegate.resolve(0, token: "stale-token")
        delegate.resolve(1, token: nil)
        let result = await second.value
        XCTAssertEqual(result.errorCode, "token_unavailable")
    }

    func testLogoutInvalidatesPendingToken() async {
        let delegate = DelayedDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let presentation = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(1)
        sdk.logout()
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "request_cancelled")
        delegate.resolve(0, token: "late-token")
        let replacement = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(2)
        delegate.resolve(1, token: nil)
        let replacementResult = await replacement.value
        XCTAssertEqual(replacementResult.errorCode, "token_unavailable")
    }

    func testReinitializationInvalidatesPendingToken() async {
        let delegate = DelayedDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let presentation = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(1)
        sdk.initialize(baseURL: URL(string: "https://other.example.com")!, urlScheme: "other", delegate: delegate)
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "request_cancelled")
        delegate.resolve(0, token: "old-environment-token")
    }

    func testCallerCancellationCompletesWhileProviderIsSuspended() async {
        let delegate = DelayedDelegate()
        let sdk = RTLSdk.shared
        sdk.initialize(baseURL: URL(string: "https://example.com")!, urlScheme: "example", delegate: delegate)
        let presentation = Task { await sdk.presentExperience() }
        await delegate.waitForRequests(1)
        presentation.cancel()
        let result = await presentation.value
        XCTAssertEqual(result.errorCode, "request_cancelled")
        delegate.resolve(0, token: "late-token")
    }

}

private final class RecordingWebView: RTLWebView {
    let handoffRequested: XCTestExpectation = {
        let expectation = XCTestExpectation(description: "SDK requests the token handoff")
        expectation.assertForOverFulfill = true
        return expectation
    }()
    private(set) var requestedURLs: [URL] = []

    // These tests exercise the SDK's authentication state machine. Document
    // replacement/clearing would start real WebKit processes even though load
    // is stubbed below, making cancellation depend on simulator startup time.
    override func prepareAuthenticationDocument() {}
    override func invalidateDocument() {}

    override func load(url: URL) {
        // Observe SDK navigation synchronously. WKWebView.url depends on a
        // separate WebKit process and must not drive these lifecycle tests.
        requestedURLs.append(url)
        handoffRequested.fulfill()
    }
}

private final class LoadingDelegate: NSObject, RTLSdkDelegate {
    private let token: String?
    private var tokenRequestContinuation: CheckedContinuation<Void, Never>?
    private var loadingStoppedContinuation: CheckedContinuation<Void, Never>?
    var loadingStates: [Bool] = []
    var readyCount = 0
    var tokenRequestCount = 0

    init(token: String? = nil) {
        self.token = token
    }

    func provideAuthToken() async -> String? {
        tokenRequestCount += 1
        tokenRequestContinuation?.resume()
        tokenRequestContinuation = nil
        return token
    }

    func onLoadingStateChanged(isLoading: Bool) {
        loadingStates.append(isLoading)
        if !isLoading {
            loadingStoppedContinuation?.resume()
            loadingStoppedContinuation = nil
        }
    }

    func onReady() {
        readyCount += 1
    }

    func reset() {
        loadingStates = []
        readyCount = 0
        tokenRequestCount = 0
    }

    func waitForTokenRequest() async {
        if tokenRequestCount > 0 { return }
        await withCheckedContinuation { tokenRequestContinuation = $0 }
    }

    func waitForLoadingToStop() async {
        if loadingStates.last == false { return }
        await withCheckedContinuation { loadingStoppedContinuation = $0 }
    }
}

@MainActor
private final class DelayedDelegate: NSObject, RTLSdkDelegate {
    nonisolated func onReady() {}
    nonisolated func onLoadingStateChanged(isLoading: Bool) {}
    private var requests: [CheckedContinuation<String?, Never>] = []
    private var waiter: (Int, CheckedContinuation<Void, Never>)?

    func provideAuthToken() async -> String? {
        await withCheckedContinuation { continuation in
            requests.append(continuation)
            if let (count, continuation) = waiter, requests.count >= count {
                waiter = nil
                continuation.resume()
            }
        }
    }

    func waitForRequests(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { waiter = (count, $0) }
    }

    func resolve(_ index: Int, token: String?) { requests[index].resume(returning: token) }
}
