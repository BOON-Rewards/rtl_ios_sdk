import XCTest
import WebKit
@testable import RTLSdk

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
        let webView = sdk.createWebView()
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
        let webView = sdk.createWebView()
        sdk.handleAppReady()
        delegate.reset()

        sdk.handleSessionExpired()
        sdk.handleSessionExpired()
        await delegate.waitForLoadingToStop()

        XCTAssertEqual(delegate.tokenRequestCount, 1)
        XCTAssertEqual(delegate.loadingStates, [true, false])
        XCTAssertEqual(delegate.readyCount, 0)
        XCTAssertTrue(webView.isHidden)
    }

    func testAuthenticationFailureStopsRecoveryWithoutReadiness() async {
        let delegate = LoadingDelegate(token: "rejected-token")
        let sdk = RTLSdk.shared
        sdk.initialize(
            baseURL: URL(string: "https://example.com")!,
            urlScheme: "example",
            delegate: delegate
        )
        let webView = sdk.createWebView()
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
    private func waitForHandoff(_ view: RTLWebView) async {
        let handoff = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            view.subviews.compactMap { $0 as? WKWebView }.first?.url?.path == "/auth/token-forward/handoff"
        }, object: nil)
        await fulfillment(of: [handoff], timeout: 3)
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
    func onReady() {}
    func onLoadingStateChanged(isLoading: Bool) {}
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
