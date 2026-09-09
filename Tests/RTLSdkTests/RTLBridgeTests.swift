import XCTest
@testable import RTLSdk

final class RTLBridgeTests: XCTestCase {
    func testParsesEverySupportedWebMessage() throws {
        let open = try RTLWebMessage.parse([
            "type": "openExternalUrl",
            "URL": "https://example.com",
            "forceExternalBrowser": false,
            "surface": "overlay",
            "merchantName": "Shop"
        ])
        guard case .openExternalUrl(let url, let surface) = open else {
            return XCTFail("Expected openExternalUrl")
        }
        XCTAssertEqual(url.absoluteString, "https://example.com")
        XCTAssertEqual(surface, .overlay)

        XCTAssertEqual(try RTLWebMessage.parse(["type": "authFailed"])?.wireName, "authFailed")
        XCTAssertEqual(try RTLWebMessage.parse(["type": "userLogout"])?.wireName, "userLogout")
        XCTAssertEqual(try RTLWebMessage.parse(["type": "appReady"])?.wireName, "appReady")
        XCTAssertEqual(
            try RTLWebMessage.parse(["type": "sessionExpired"])?.wireName,
            "sessionExpired"
        )
        XCTAssertEqual(
            try RTLWebMessage.parse(["type": "requestLocationPermission"])?.wireName,
            "requestLocationPermission"
        )
        XCTAssertEqual(
            try RTLWebMessage.parse(["type": "requestNativeCapabilities"])?.wireName,
            "requestNativeCapabilities"
        )

        let haptic = try RTLWebMessage.parse([
            "type": "hapticPlay",
            "payload": [
                "version": 1,
                "events": [["at": 0, "type": "impact"]]
            ]
        ])
        guard case .hapticPlay(let pattern) = haptic else {
            return XCTFail("Expected hapticPlay")
        }
        XCTAssertEqual(pattern.events.first?.kind, .impact)
    }

    func testIgnoresUnknownMessages() throws {
        XCTAssertNil(try RTLWebMessage.parse(["type": "somethingElse"]))
    }

    func testForegroundLocationRequiresACorrelationId() throws {
        guard case .requestLocation(let requestId) = try RTLWebMessage.parse([
            "type": "requestLocation", "requestId": "location-1"
        ]) else { return XCTFail("Expected requestLocation") }
        XCTAssertEqual(requestId, "location-1")
        for value in ["", String(repeating: "a", count: 129), 42] as [Any] {
            XCTAssertThrowsError(try RTLWebMessage.parse(["type": "requestLocation", "requestId": value]))
        }
        XCTAssertThrowsError(try RTLWebMessage.parse(["type": "requestLocation"]))
    }

    func testRejectsOpenMessageWithoutSurface() {
        XCTAssertThrowsError(try RTLWebMessage.parse([
            "type": "openExternalUrl",
            "URL": "https://example.com",
            "forceExternalBrowser": false
        ]))
    }

    func testParsesEveryUrlSurfaceWithoutUsingTheLegacyFlagForRouting() throws {
        for surface in RTLSurface.allCases {
            let parsed = try RTLWebMessage.parse([
                "type": "openExternalUrl",
                "URL": "https://example.com",
                "forceExternalBrowser": true,
                "surface": surface.rawValue
            ])
            guard case .openExternalUrl(_, let parsedSurface) = parsed else {
                return XCTFail("Expected openExternalUrl for \(surface.rawValue)")
            }
            XCTAssertEqual(parsedSurface, surface)
        }
    }

    func testRejectsInvalidHapticMessage() {
        XCTAssertThrowsError(try RTLWebMessage.parse([
            "type": "hapticPlay",
            "payload": [
                "version": 1,
                "events": [["at": -1, "type": "impact"]]
            ]
        ]))
    }

    func testForwardsFutureCompletionInsideFixedEnvelope() throws {
        let raw = try serializeNativeMessage(.overlayCompleted, fields: [
            "completionType": "futureFlow",
            "data": ["futureField": "a&b", "type": "logoutRequested"]
        ])
        let encoded = try XCTUnwrap(raw.data(using: .utf8))
        let message = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        XCTAssertEqual(message["type"] as? String, "overlayCompleted")
        XCTAssertEqual(message["completionType"] as? String, "futureFlow")
        let data = try XCTUnwrap(message["data"] as? [String: String])
        XCTAssertEqual(data["futureField"], "a&b")
        XCTAssertEqual(data["type"], "logoutRequested")
    }

    func testSerializesEverySupportedNativeMessageWithAFlatType() throws {
        let types: [RTLNativeMessageType] = [
            .nativeCapabilities,
            .logoutRequested,
            .locationPermissionStatus,
            .locationUpdate,
            .locationResult,
            .overlayCompleted
        ]

        for type in types {
            let raw = try serializeNativeMessage(type, fields: ["value": "kept"])
            let data = try XCTUnwrap(raw.data(using: .utf8))
            let message = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: String]
            )
            XCTAssertEqual(message["type"], type.rawValue)
            XCTAssertEqual(message["value"], "kept")
        }
    }
}
