import XCTest
@testable import RTLSdk

final class RTLLocationAuthorizationTests: XCTestCase {
    override func tearDown() {
        RTLSdk.shared.disableLocationFeatures()
        super.tearDown()
    }

    func testWebPermissionRequestDoesNotEnableLocationFeatures() {
        let sdk = RTLSdk.shared
        sdk.disableLocationFeatures()

        sdk.handleLocationPermissionRequest()

        XCTAssertFalse(sdk.isLocationFeaturesEnabled)
    }

    func testHyperlocalOffersRequireWebViewSessionCookie() async {
        let service = RTLHyperlocalOffersService(
            baseURL: URL(string: "https://example.com")!,
            externalChapterId: nil,
            sessionCookieHeader: { _ in nil }
        )

        do {
            _ = try await service.fetchHyperlocalOffers(
                latitude: 40.1772,
                longitude: 44.5035
            )
            XCTFail("Expected hyperlocal offers to reject a missing session")
        } catch RTLHyperlocalOffersServiceError.unauthenticated {
            // Expected: no network request is made without the WebView session.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
