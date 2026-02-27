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
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false

        // Enable debug mode when running from Xcode (DEBUG builds)
        #if DEBUG
        self.debugMode = true
        print("[RTLSdk] 🔧 Debug mode enabled - using standard location updates for GPX testing")
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

    /// Request always (background) authorization
    /// - Parameter notifyOnAlreadyGranted: If true, calls onPermissionChange even if already granted. Default is false to avoid duplicate notifications.
    func requestPermission(notifyOnAlreadyGranted: Bool = false) {
        let currentStatus = authorizationStatus
        print("[RTLSdk] Requesting location permission... Current status: \(currentStatus.rawValue)")

        switch currentStatus {
        case .notDetermined:
            print("[RTLSdk] Status not determined, showing permission dialog...")
            locationManager.requestAlwaysAuthorization()
        case .authorizedAlways:
            print("[RTLSdk] Already have Always authorization")
            if notifyOnAlreadyGranted {
                onPermissionChange?(true)
            }
            startMonitoring()
            requestLocation()
        case .authorizedWhenInUse:
            print("[RTLSdk] Have WhenInUse, requesting upgrade to Always...")
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            print("[RTLSdk] Permission denied/restricted. User must enable in Settings.")
            if notifyOnAlreadyGranted {
                onPermissionChange?(false)
            }
        @unknown default:
            print("[RTLSdk] Unknown authorization status")
            locationManager.requestAlwaysAuthorization()
        }
    }

    /// Start monitoring location changes
    func startMonitoring() {
        guard hasBackgroundPermission else {
            print("[RTLSdk] Cannot start monitoring: no background permission")
            return
        }

        if debugMode {
            print("[RTLSdk] 🔧 Starting STANDARD location updates (debug mode for GPX testing)")
            locationManager.startUpdatingLocation()
        } else {
            print("[RTLSdk] Starting significant location monitoring")
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }

    /// Stop monitoring location changes
    func stopMonitoring() {
        print("[RTLSdk] Stopping location monitoring")
        if debugMode {
            locationManager.stopUpdatingLocation()
        } else {
            locationManager.stopMonitoringSignificantLocationChanges()
        }
    }

    /// Request a single location update
    func requestLocation() {
        guard hasAnyPermission else {
            print("[RTLSdk] Cannot request location: no permission")
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

        print("[RTLSdk] Location authorization changed: \(status.rawValue), background: \(granted), whenInUse: \(hasWhenInUse)")

        onPermissionChange?(granted)

        if granted {
            startMonitoring()
            // Request initial location
            requestLocation()
        } else if hasWhenInUse {
            // We have WhenInUse but not Always - can still get location
            print("[RTLSdk] Have WhenInUse permission, requesting location...")
            requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("[RTLSdk] Location update: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        onLocationUpdate?(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[RTLSdk] Location error: \(error.localizedDescription)")
    }
}
