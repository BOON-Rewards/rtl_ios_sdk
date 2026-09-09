import XCTest
import CoreLocation
import UserNotifications
@testable import RTLSdk

@MainActor
final class RTLHostCoexistenceTests: XCTestCase {
    func testForegroundNotificationHelperIgnoresHostNotifications() {
        let content = UNMutableNotificationContent()
        let host = UNNotificationRequest(identifier: "host-message", content: content, trigger: nil)
        let sdk = UNNotificationRequest(
            identifier: RTLNotificationManager.identifierPrefix + "test", content: content, trigger: nil
        )
        XCTAssertNil(RTLSdk.notificationPresentationOptions(for: host))
        XCTAssertEqual(RTLSdk.notificationPresentationOptions(for: sdk), [.banner, .sound])
    }

    func testDisableStopsOnlyNamespacedRegionsIncludingPreviousLaunches() {
        let location = RecordingLocationManager()
        let host = region("host-delivery")
        let legacy = region("unprefixed-store")
        let sdk = region(RTLGeofenceManager.identifierPrefix + "store")
        location.regions = [host, legacy, sdk]
        let manager = RTLGeofenceManager(locationManager: location)
        manager.stopMonitoring()
        XCTAssertEqual(location.stopped, [sdk.identifier])
        XCTAssertEqual(Set(location.regions.map(\.identifier)), [host.identifier, legacy.identifier])
    }

    func testUpdateRespectsHostCapacityAndRestoresSDKOwnership() {
        let location = RecordingLocationManager()
        location.regions = Set((0..<19).map { region("host-\($0)") })
        let stale = region(RTLGeofenceManager.identifierPrefix + "old")
        location.regions.insert(stale)
        let manager = RTLGeofenceManager(locationManager: location)
        manager.updateGeofences(for: [store("new"), store("extra")])
        XCTAssertEqual(location.stopped, [stale.identifier])
        XCTAssertEqual(location.started.map(\.identifier), [RTLGeofenceManager.identifierPrefix + "new"])
        XCTAssertEqual(location.regions.count, 20)
        manager.updateGeofences(for: [store("new"), store("extra")])
        XCTAssertEqual(location.started.count, 1)
    }

    func testForeignAndLateRegionCallbacksAreIgnored() {
        let location = RecordingLocationManager()
        let manager = RTLGeofenceManager(locationManager: location)
        var entries: [String] = []
        manager.onGeofenceEnter = { entries.append($0.id) }
        manager.updateGeofences(for: [store("store")])
        let sdkRegion = location.started[0]
        let foreign = region("store")
        manager.locationManager(location, didEnterRegion: foreign)
        manager.locationManager(location, didStartMonitoringFor: foreign)
        manager.locationManager(location, didEnterRegion: sdkRegion)
        XCTAssertEqual(entries, ["store"])
        XCTAssertTrue(location.requestedStates.isEmpty)
        manager.stopMonitoring()
        manager.locationManager(location, didEnterRegion: sdkRegion)
        manager.locationManager(location, didStartMonitoringFor: sdkRegion)
        XCTAssertEqual(entries, ["store"])
        XCTAssertTrue(location.requestedStates.isEmpty)
    }

    func testRetainedRegionStateIsRequestedOnceAndInsideStateDeliversOffer() {
        let location = RecordingLocationManager()
        let retained = region(RTLGeofenceManager.identifierPrefix + "store")
        location.regions = [retained, region("host-region")]
        let manager = RTLGeofenceManager(locationManager: location)
        var entries: [String] = []
        manager.onGeofenceEnter = { entries.append($0.id) }

        manager.updateGeofences(for: [store("store"), store("new")])
        XCTAssertEqual(location.requestedStates, [retained.identifier])
        XCTAssertEqual(location.started.map(\.identifier), [RTLGeofenceManager.identifierPrefix + "new"])
        manager.locationManager(location, didDetermineState: .inside, for: retained)
        XCTAssertEqual(entries, ["store"])

        manager.updateGeofences(for: [store("store"), store("new")])
        XCTAssertEqual(location.requestedStates, [retained.identifier])
        XCTAssertEqual(location.started.count, 1)
    }

    private func region(_ id: String) -> CLCircularRegion {
        CLCircularRegion(center: CLLocationCoordinate2D(latitude: 42, longitude: -71), radius: 100, identifier: id)
    }

    private func store(_ id: String) -> RTLStore {
        RTLStore(id: id, name: id, merchantId: id, latitude: 42, longitude: -71)
    }
}

private final class RecordingLocationManager: CLLocationManager {
    var regions: Set<CLRegion> = []
    var stopped: [String] = []
    var started: [CLRegion] = []
    var requestedStates: [String] = []
    override var monitoredRegions: Set<CLRegion> { regions }
    override func startMonitoring(for region: CLRegion) {
        started.append(region)
        regions.insert(region)
    }
    override func stopMonitoring(for region: CLRegion) {
        stopped.append(region.identifier)
        regions.remove(region)
    }
    override func requestState(for region: CLRegion) { requestedStates.append(region.identifier) }
}
