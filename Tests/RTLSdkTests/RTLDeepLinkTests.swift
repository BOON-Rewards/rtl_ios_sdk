import XCTest
@testable import RTLSdk

final class RTLDeepLinkTests: XCTestCase {
    func testOpenRouteGivesRedirectPrecedence() throws {
        let url = try XCTUnwrap(URL(
            string: "example://rtl-sdk/open?rtlEventId=event-1&rtlRedirectUrl=https%3A%2F%2Fexample.com%2Foffers"
        ))

        XCTAssertEqual(
            parseRTLDeepLink(url, configuredScheme: "example"),
            .open(rtlEventId: nil, rtlRedirectUrl: "https://example.com/offers")
        )
    }

    func testDefaultEventAndCallbackRoutes() throws {
        let defaultURL = try XCTUnwrap(URL(string: "example://rtl-sdk/open"))
        let eventURL = try XCTUnwrap(URL(string: "example://rtl-sdk/open?rtlEventId=event-1"))
        let blankRedirectURL = try XCTUnwrap(URL(
            string: "example://rtl-sdk/open?rtlEventId=event-1&rtlRedirectUrl=%20"
        ))
        let callbackURL = try XCTUnwrap(URL(string: "example://rtl-sdk/callback?redirectUrl=x"))

        XCTAssertEqual(
            parseRTLDeepLink(defaultURL, configuredScheme: "example"),
            .open(rtlEventId: nil, rtlRedirectUrl: nil)
        )
        XCTAssertEqual(
            parseRTLDeepLink(eventURL, configuredScheme: "example"),
            .open(rtlEventId: "event-1", rtlRedirectUrl: nil)
        )
        XCTAssertEqual(
            parseRTLDeepLink(blankRedirectURL, configuredScheme: "example"),
            .open(rtlEventId: "event-1", rtlRedirectUrl: nil)
        )
        XCTAssertEqual(
            parseRTLDeepLink(callbackURL, configuredScheme: "example"),
            .callback(callbackURL)
        )
    }

    func testRejectsLegacyAndUnrelatedRoutes() throws {
        let values = [
            "example://rtlSdk",
            "example://rtl-callback",
            "example://rtl-sdk/unknown",
            "other://rtl-sdk/open"
        ]

        for value in values {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(parseRTLDeepLink(url, configuredScheme: "example"))
        }
    }
}
