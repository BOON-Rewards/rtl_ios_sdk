import XCTest
import CoreLocation
import UIKit
@testable import RTLSdk

@MainActor
final class RTLForegroundLocationTests: XCTestCase {
    func testRequestsOnlyWhenInUseAndStopsAfterOneFix() {
        let location = ForegroundLocationRecorder()
        let request = RTLForegroundLocation(manager: location, canRequest: { true })
        var results: [[String: Any]] = []
        request.request { results.append($0) }
        XCTAssertEqual(location.whenInUseRequests, 1)
        XCTAssertEqual(location.alwaysRequests, 0)
        XCTAssertEqual(location.starts, 0)
        location.status = .authorizedWhenInUse
        request.locationManagerDidChangeAuthorization(location)
        request.locationManagerDidChangeAuthorization(location)
        XCTAssertEqual(location.starts, 1)
        request.locationManager(location, didUpdateLocations: [CLLocation(latitude: 42, longitude: -71)])
        request.locationManager(location, didUpdateLocations: [CLLocation(latitude: 43, longitude: -72)])
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?["lat"] as? Double, 42)
        XCTAssertGreaterThan(location.stops, 0)
        XCTAssertFalse(location.allowsBackgroundLocationUpdates)
    }

    func testDeniedPermissionDoesNotStartLocationOrUpgradeAuthorization() {
        let location = ForegroundLocationRecorder()
        location.status = .denied
        let request = RTLForegroundLocation(manager: location, canRequest: { true })
        var result: [String: Any] = [:]
        request.request { result = $0 }
        XCTAssertEqual(result["error"] as? String, "permissionDenied")
        XCTAssertEqual(location.starts, 0)
        XCTAssertEqual(location.alwaysRequests + location.whenInUseRequests, 0)
    }

    func testMissingConfigurationOrInactiveHostFailsWithoutPrompting() {
        let location = ForegroundLocationRecorder()
        let request = RTLForegroundLocation(manager: location, canRequest: { false })
        var result: [String: Any] = [:]
        request.request { result = $0 }
        XCTAssertEqual(result["error"] as? String, "unavailable")
        XCTAssertEqual(location.whenInUseRequests + location.alwaysRequests + location.starts, 0)
    }

    func testRetiringDocumentSuppressesLateLocationAndPermissionCallbacks() {
        let location = ForegroundLocationRecorder()
        let request = RTLForegroundLocation(manager: location, canRequest: { true })
        request.request { _ in XCTFail("Cancelled document received a location") }
        request.cancel()
        location.status = .authorizedWhenInUse
        request.locationManagerDidChangeAuthorization(location)
        request.locationManager(location, didUpdateLocations: [CLLocation(latitude: 42, longitude: -71)])
        XCTAssertEqual(location.starts, 0)
    }

    func testBackgroundingEndsForegroundRequestAndAllowsLaterRetry() {
        let location = ForegroundLocationRecorder()
        location.status = .authorizedAlways
        let request = RTLForegroundLocation(manager: location, canRequest: { true })
        var results: [[String: Any]] = []
        request.request { results.append($0) }
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        XCTAssertEqual(results.first?["error"] as? String, "unavailable")
        request.request { results.append($0) }
        request.locationManager(location, didUpdateLocations: [CLLocation(latitude: 42, longitude: -71)])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.last?["lat"] as? Double, 42)
        XCTAssertEqual(location.alwaysRequests, 0)
    }
}

private final class ForegroundLocationRecorder: CLLocationManager {
    var status = CLAuthorizationStatus.notDetermined
    var whenInUseRequests = 0
    var alwaysRequests = 0
    var starts = 0
    var stops = 0
    override var authorizationStatus: CLAuthorizationStatus { status }
    override func requestWhenInUseAuthorization() { whenInUseRequests += 1 }
    override func requestAlwaysAuthorization() { alwaysRequests += 1 }
    override func startUpdatingLocation() { starts += 1 }
    override func stopUpdatingLocation() { stops += 1 }
}
