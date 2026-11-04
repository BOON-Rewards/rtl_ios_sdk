import XCTest
@testable import RTLSdk

final class RTLDeepLinkTests: XCTestCase {
    func testOpenRouteGivesRedirectPrecedence() throws {
        let url = try XCTUnwrap(URL(
            string: "example://rtl-callback/open?rtlEventId=event-1&rtlRedirectUrl=https%3A%2F%2Fexample.com%2Foffers"
        ))

        XCTAssertEqual(
            parseRTLDeepLink(url, configuredScheme: "example"),
            .open(rtlEventId: nil, rtlRedirectUrl: "https://example.com/offers")
        )
    }

    func testDefaultEventAndCallbackRoutes() throws {
        let defaultURL = try XCTUnwrap(URL(string: "example://rtl-callback/open"))
        let eventURL = try XCTUnwrap(URL(string: "example://rtl-callback/open?rtlEventId=event-1"))
        let blankRedirectURL = try XCTUnwrap(URL(
            string: "example://rtl-callback/open?rtlEventId=event-1&rtlRedirectUrl=%20"
        ))
        let callbackURL = try XCTUnwrap(URL(string: "example://rtl-callback/callback?redirectUrl=x"))

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

    func testPathlessCallbackAliasPreservesTheWholeURL() throws {
        for value in [
            "example://rtl-callback",
            "EXAMPLE://RTL-CALLBACK?redirectUrl=https%3A%2F%2Fexample.com&result=linked",
            "example://rtl-callback/callback?resume=message&completionType=openBanking&result=linked"
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertEqual(parseRTLDeepLink(url, configuredScheme: "example"), .callback(url))
            XCTAssertNil(parseRTLDeepLink(url, configuredScheme: nil))
        }
    }

    func testOpenRouteDecodesFormEncodedSpacesAndLiteralPluses() throws {
        let url = try XCTUnwrap(URL(string: "example://rtl-callback/open?rtlEventId=event%2B1&rtlRedirectUrl=+"))
        XCTAssertEqual(
            parseRTLDeepLink(url, configuredScheme: "example"),
            .open(rtlEventId: "event+1", rtlRedirectUrl: nil)
        )
    }

    func testRejectsUnrelatedRoutes() throws {
        let values = [
            "example://rtl-callback/unknown",
            "other://rtl-callback/open",
            "example://rtl-callback/",
            "example://rtl-callback/open/extra",
            "example://rtl-callback.evil.example/open",
            "example://user@rtl-callback/open",
            "example://rtl-callback:123/open"
        ]

        for value in values {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(parseRTLDeepLink(url, configuredScheme: "example"))
        }
    }
}
