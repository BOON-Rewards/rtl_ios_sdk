import Foundation
import CoreLocation

/// Manages only RTL-owned regions; CLLocationManager registrations are shared by the app.
class RTLGeofenceManager: NSObject, CLLocationManagerDelegate {
    static let identifierPrefix = "com.affinaloyalty.rtlsdk.store."
    private let locationManager: CLLocationManager
    private var monitoredStores: [String: RTLStore] = [:]

    var onGeofenceEnter: ((RTLStore) -> Void)?

    private let maxGeofences = 20
    private let geofenceRadius: CLLocationDistance = 100

    init(locationManager: CLLocationManager = CLLocationManager()) {
        self.locationManager = locationManager
        super.init()
        locationManager.delegate = self
    }

    private func storeId(for region: CLRegion) -> String? {
        guard region.identifier.hasPrefix(Self.identifierPrefix) else { return nil }
        return String(region.identifier.dropFirst(Self.identifierPrefix.count))
    }

    func updateGeofences(for stores: [RTLStore]) {
        let regions = locationManager.monitoredRegions
        let hostRegionCount = regions.filter { storeId(for: $0) == nil }.count
        let capacity = max(0, maxGeofences - hostRegionCount)
        var desiredStores: [String: RTLStore] = [:]
        for store in stores where desiredStores.count < capacity {
            desiredStores[store.id] = store
        }
        let desiredIds = Set(desiredStores.keys)
        let registeredIds = Set(regions.compactMap { storeId(for: $0) })
        let adoptedIds = registeredIds.intersection(desiredIds).subtracting(monitoredStores.keys)
        // Include registrations still waiting for Core Location's acknowledgment.
        let existingIds = registeredIds.union(monitoredStores.keys)
        let addedIds = desiredIds.subtracting(existingIds)
        let removedIds = existingIds.subtracting(desiredIds)

        if Set(stores.map { $0.id }).count > capacity {
            RTLLog.debug(.geofence, "Geofence capacity limited to \(capacity) stores; \(hostRegionCount) regions belong to the host")
        }
        if addedIds.isEmpty && removedIds.isEmpty && adoptedIds.isEmpty {
            RTLLog.debug(.geofence, "Geofences unchanged, skipping registration update")
        } else {
            RTLLog.debug(.geofence, "Updating geofences: removing \(removedIds.count), adding \(addedIds.count), adopting \(adoptedIds.count)")
        }

        for region in regions {
            if let id = storeId(for: region), !desiredIds.contains(id) {
                locationManager.stopMonitoring(for: region)
                RTLLog.debug(.geofence, "Stopped monitoring RTL geofence: \(id)")
            }
        }
        monitoredStores = desiredStores

        // Retained regions do not produce a new registration callback. Check
        // their state once after restoring the store data, including already-inside cases.
        for region in regions {
            if let id = storeId(for: region), adoptedIds.contains(id) {
                RTLLog.debug(.geofence, "Checking current state of retained RTL geofence: \(id)")
                locationManager.requestState(for: region)
            }
        }

        for store in desiredStores.values where addedIds.contains(store.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude),
                radius: geofenceRadius,
                identifier: Self.identifierPrefix + store.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false
            RTLLog.debug(.geofence, "Registering RTL geofence: \(store.id), radius \(geofenceRadius)m")
            locationManager.startMonitoring(for: region)
        }
        RTLLog.debug(.geofence, "Monitoring \(desiredStores.count) RTL geofences; \(hostRegionCount) regions belong to the host")
    }

    /// Stops RTL regions, including registrations retained across app launches.
    func stopMonitoring() {
        monitoredStores.removeAll()
        for region in locationManager.monitoredRegions where storeId(for: region) != nil {
            locationManager.stopMonitoring(for: region)
        }
        RTLLog.debug(.geofence, "Stopped RTL geofence monitoring")
    }

    func getStore(id: String) -> RTLStore? {
        monitoredStores[id]
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let id = storeId(for: region), let store = monitoredStores[id] else { return }
        RTLLog.debug(.geofence, "Entered RTL geofence: \(id)")
        onGeofenceEnter?(store)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let id = storeId(for: region) else { return }
        RTLLog.debug(.geofence, "Exited RTL geofence: \(id)")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        guard let region, let id = storeId(for: region) else { return }
        monitoredStores.removeValue(forKey: id)
        RTLLog.error(.geofence, "Geofence monitoring failed for \(id): \(error.localizedDescription)")
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        guard let id = storeId(for: region) else { return }
        guard monitoredStores[id] != nil else {
            // Registration can finish after disable/update removed this store.
            locationManager.stopMonitoring(for: region)
            return
        }
        RTLLog.info(.geofence, "Started monitoring geofence: \(region.identifier)")
        locationManager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard let id = storeId(for: region) else { return }
        switch state {
        case .inside:
            RTLLog.debug(.geofence, "Already inside RTL geofence: \(id)")
            self.locationManager(manager, didEnterRegion: region)
        case .outside:
            RTLLog.debug(.geofence, "Outside RTL geofence: \(id)")
        case .unknown:
            RTLLog.debug(.geofence, "Unknown state for RTL geofence: \(id)")
        @unknown default:
            break
        }
    }
}
