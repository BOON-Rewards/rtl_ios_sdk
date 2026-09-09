import Foundation
import CoreLocation

/// Manages geofences around stores
class RTLGeofenceManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private var monitoredStores: [String: RTLStore] = [:]

    var onGeofenceEnter: ((RTLStore) -> Void)?

    // iOS limits to 20 geofences per app
    private let maxGeofences = 20
    private let geofenceRadius: CLLocationDistance = 100 // 100 meters

    override init() {
        super.init()
        locationManager.delegate = self
    }

    /// Update geofences for the given stores
    /// Only updates if stores have changed significantly to avoid resetting active geofences
    func updateGeofences(for stores: [RTLStore]) {
        // Sort stores by distance from current location would be ideal,
        // but for now just take first 20
        let storesToMonitor = Array(stores.prefix(maxGeofences))
        let newStoreIds = Set(storesToMonitor.map { $0.id })
        let existingStoreIds = Set(monitoredStores.keys)

        // Check if we need to update at all
        if newStoreIds == existingStoreIds {
            RTLLog.warn(.geofence, "🔄 Geofences unchanged, skipping update")
            return
        }

        // Find stores to remove and add
        let storesToRemove = existingStoreIds.subtracting(newStoreIds)
        let storesToAdd = storesToMonitor.filter { !existingStoreIds.contains($0.id) }

        RTLLog.debug(.geofence, "🎯 Updating geofences: removing \(storesToRemove.count), adding \(storesToAdd.count)")

        // Remove old stores from our tracking dict FIRST
        // This ensures we don't accumulate failed registrations
        for storeId in storesToRemove {
            monitoredStores.removeValue(forKey: storeId)
            RTLLog.debug(.geofence, "❌ Removed: \(storeId)")
        }

        // Then stop monitoring any matching regions in iOS
        for region in locationManager.monitoredRegions {
            if let circularRegion = region as? CLCircularRegion,
               storesToRemove.contains(circularRegion.identifier) {
                locationManager.stopMonitoring(for: region)
            }
        }

        // Add new geofences (limit to remaining capacity)
        let remainingCapacity = maxGeofences - monitoredStores.count
        let storesToActuallyAdd = Array(storesToAdd.prefix(remainingCapacity))

        if storesToActuallyAdd.count < storesToAdd.count {
            RTLLog.debug(.geofence, "⚠️ Only adding \(storesToActuallyAdd.count) of \(storesToAdd.count) stores (capacity limit)")
        }

        for store in storesToActuallyAdd {
            let center = CLLocationCoordinate2D(latitude: store.latitude, longitude: store.longitude)
            let region = CLCircularRegion(
                center: center,
                radius: geofenceRadius,
                identifier: store.id
            )
            region.notifyOnEntry = true
            region.notifyOnExit = false

            RTLLog.debug(.geofence, "Added a geofence with radius \(geofenceRadius)m")

            locationManager.startMonitoring(for: region)
            monitoredStores[store.id] = store
        }

        RTLLog.debug(.geofence, "✅ Now monitoring \(monitoredStores.count) geofences")
    }

    /// Stop all geofence monitoring
    func stopMonitoring() {
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        monitoredStores.removeAll()
        RTLLog.debug(.geofence, "Stopped all geofence monitoring")
    }

    /// Get store by ID
    func getStore(id: String) -> RTLStore? {
        return monitoredStores[id]
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        RTLLog.debug(.geofence, "🚨 GEOFENCE ENTERED: \(region.identifier)")

        guard let circularRegion = region as? CLCircularRegion,
              let store = monitoredStores[circularRegion.identifier] else {
            RTLLog.error(.geofence, "❌ Store not found for geofence: \(region.identifier)")
            return
        }

        RTLLog.debug(.geofence, "Matched the entered geofence to a hyperlocal offer")
        onGeofenceEnter?(store)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        // Currently not handling exit events
        RTLLog.debug(.geofence, "Exited geofence: \(region.identifier)")
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        let regionId = region?.identifier ?? "unknown"
        RTLLog.error(.geofence, "Geofence monitoring failed for \(regionId): \(error.localizedDescription)")

        // Remove failed registration from tracking dict
        if let id = region?.identifier {
            monitoredStores.removeValue(forKey: id)
        }
    }

    func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        RTLLog.info(.geofence, "Started monitoring geofence: \(region.identifier)")
        // Request state to check if we're already inside
        locationManager.requestState(for: region)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        switch state {
        case .inside:
            RTLLog.debug(.geofence, "📍 Already INSIDE geofence: \(region.identifier)")
            // Trigger entry callback since we're already inside
            if let circularRegion = region as? CLCircularRegion,
               let store = monitoredStores[circularRegion.identifier] {
                RTLLog.debug(.geofence, "🏪 Triggering entry for: \(store.name)")
                onGeofenceEnter?(store)
            }
        case .outside:
            RTLLog.debug(.geofence, "📍 Outside geofence: \(region.identifier)")
        case .unknown:
            RTLLog.debug(.geofence, "📍 Unknown state for geofence: \(region.identifier)")
        @unknown default:
            break
        }
    }
}
