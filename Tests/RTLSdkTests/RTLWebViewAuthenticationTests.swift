import XCTest
import WebKit
@_spi(RTLExample) @testable import RTLSdk

@MainActor
final class RTLWebViewAuthenticationTests: XCTestCase {
    func testClearingAuthenticationPreservesDocumentAndRemovesChallengeHandler() throws {
        let view = RTLWebView(sdk: .shared)
        let handler = ExampleChallengeHandler()
        view.setAuthenticationChallengeHandlerForExample(handler) {
            XCTFail("Cleared failure callback must not run")
        }
        view.prepareAuthenticationDocument()
        let document = try XCTUnwrap(view.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertFalse(document.configuration.websiteDataStore.isPersistent)

        view.setAuthenticationChallengeHandlerForExample(nil)

        // The existing page must remain available to process logoutRequested.
        XCTAssertTrue(view.subviews.contains { $0 === document })
        let challenge = URLAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: "example.com", port: 443,
                protocol: "https", realm: "Boon staging", authenticationMethod: NSURLAuthenticationMethodHTTPBasic),
            proposedCredential: nil, previousFailureCount: 0,
            failureResponse: nil, error: nil, sender: ChallengeSender()
        )
        var disposition: URLSession.AuthChallengeDisposition?
        view.webView(document, didReceive: challenge) { result, credential in
            disposition = result
            XCTAssertNil(credential)
        }
        XCTAssertEqual(disposition, .performDefaultHandling)
        XCTAssertEqual(handler.challengeCount, 0)

        // The next login applies the cleared handler's persistent storage mode.
        view.prepareAuthenticationDocument()
        let nextDocument = try XCTUnwrap(view.subviews.compactMap { $0 as? WKWebView }.first)
        XCTAssertFalse(document === nextDocument)
        XCTAssertTrue(nextDocument.configuration.websiteDataStore.isPersistent)
    }
}

private final class ExampleChallengeHandler: NSObject, RTLAuthenticationChallengeHandler {
    var challengeCount = 0

    func response(to challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        challengeCount += 1
        return (.cancelAuthenticationChallenge, nil)
    }
}

private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
}
