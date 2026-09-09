import Foundation
import CoreLocation

/// Manages location permissions and tracking
class RTLLocationManager: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private weak var sdk: RTLSdk?

    var onLocationUpdate: ((CLLocation) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?

    /// Enable debug mode for testing with GPX simulation
    /// When true, uses standard location updates instead of significant changes
    var debugMode: Bool = false

    init(sdk: RTLSdk) {
        self.sdk = sdk
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 100 // Update every 100 meters

        if Self.appSupportsBackgroundLocation {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
        } else {
            RTLLog.debug(.location, "⚠️ Background location mode is not enabled. Add UIBackgroundModes/location to Info.plist before enabling background location features.")
        }

        // Enable debug mode when running from Xcode (DEBUG builds)
        #if DEBUG
        self.debugMode = true
        RTLLog.debug(.location, "🔧 Debug mode enabled - using standard location updates for GPX testing")
        #endif
    }

    /// Get current authorization status (iOS 13 compatible)
    private var authorizationStatus: CLAuthorizationStatus {
        if #available(iOS 14.0, *) {
            return locationManager.authorizationStatus
        } else {
            return CLLocationManager.authorizationStatus()
        }
    }

    /// Check if background (always) permission is granted
    var hasBackgroundPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    /// Check if any location permission is granted
    var hasAnyPermission: Bool {
        let status = authorizationStatus
        return status == .authorizedAlways || status == .authorizedWhenInUse
    }

    /// Current location if available
    var currentLocation: CLLocation? {
        locationManager.location
    }

    private static var appSupportsBackgroundLocation: Bool {
        guard let backgroundModes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] else {
            return false
        }
        return backgroundModes.contains("location")
    }

    /// Request always (background) authorization
    /// - Parameter notifyOnAlreadyGranted: If true, calls onPermissionChange even if already granted. Default is false to avoid duplicate notifications.
    func requestPermission(notifyOnAlreadyGranted: Bool = false) {
        let currentStatus = authorizationStatus
        RTLLog.info(.location, "Requesting location permission... Current status: \(currentStatus.rawValue)")

        switch currentStatus {
        case .notDetermined:
            RTLLog.debug(.location, "Status not determined, showing permission dialog...")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            RTLLog.info(.location, "Already have Always authorization")
            if notifyOnAlreadyGranted {
                onPermissionChange?(true)
            }
            startMonitoring()
            requestLocation()
        case .authorizedWhenInUse:
            RTLLog.debug(.location, "Have WhenInUse, requesting upgrade to Always...")
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            RTLLog.error(.location, "Permission denied/restricted. User must enable in Settings.")
            if notifyOnAlreadyGranted {
                onPermissionChange?(false)
            }
        @unknown default:
            RTLLog.debug(.location, "Unknown authorization status")
            locationManager.requestAlwaysAuthorization()
        }
    }

    /// Start monitoring location changes
    func startMonitoring() {
        guard hasBackgroundPermission else {
            RTLLog.error(.location, "Cannot start monitoring: no background permission")
            return
        }

        if debugMode {
            RTLLog.debug(.location, "🔧 Starting STANDARD location updates (debug mode for GPX testing)")
            locationManager.startUpdatingLocation()
        } else {
            RTLLog.info(.location, "Starting significant location monitoring")
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    /// Stop monitoring location changes
    func stopMonitoring() {
        RTLLog.debug(.location, "Stopping location monitoring")
        if debugMode {
            locationManager.stopUpdatingLocation()
        } else {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    /// Request a single location update
    func requestLocation() {
        guard hasAnyPermission else {
            RTLLog.error(.location, "Cannot request location: no permission")
            return
        }
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    // iOS 14+ authorization change handler
    @available(iOS 14.0, *)
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorizationChange(status: manager.authorizationStatus)
    }

    // iOS 13 authorization change handler
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        // Only handle on iOS 13, iOS 14+ uses locationManagerDidChangeAuthorization
        if #available(iOS 14.0, *) {
            return
        }
        handleAuthorizationChange(status: status)
    }

    private func handleAuthorizationChange(status: CLAuthorizationStatus) {
        let granted = status == .authorizedAlways
        let hasWhenInUse = status == .authorizedWhenInUse

        RTLLog.debug(.location, "Location authorization changed: \(status.rawValue), background: \(granted), whenInUse: \(hasWhenInUse)")

        onPermissionChange?(granted)

        if granted {
            startMonitoring()
            // Request initial location
            requestLocation()
        } else if hasWhenInUse {
            // We have WhenInUse but not Always - can still get location
            RTLLog.debug(.location, "Have WhenInUse permission, requesting location...")
            requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        RTLLog.debug(.location, "Location update received")
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        RTLLog.error(.location, "Location error: \(error.localizedDescription)")
    }
}
