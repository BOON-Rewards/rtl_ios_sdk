import CoreLocation
import UIKit

/// A document-scoped foreground request. Does not enable hyperlocal features.
final class RTLForegroundLocation: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let canRequest: () -> Bool
    private var completion: (([String: Any]) -> Void)?
    private var timeout: DispatchWorkItem?
    private var requestingPosition = false
    private var backgroundObserver: NSObjectProtocol?

    init(
        manager: CLLocationManager = CLLocationManager(),
        canRequest: @escaping () -> Bool = {
            UIApplication.shared.applicationState == .active &&
            !(Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String ?? "").isEmpty
        }
    ) {
        self.manager = manager
        self.canRequest = canRequest
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.finish(["error": "unavailable"]) }
    }

    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        timeout?.cancel()
        manager.stopUpdatingLocation()
    }

    func request(completion: @escaping ([String: Any]) -> Void) {
        guard self.completion == nil, canRequest() else {
            completion(["error": "unavailable"])
            return
        }
        self.completion = completion
        let timeout = DispatchWorkItem { [weak self] in self?.finish(["error": "timeout"]) }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            handleAuthorization()
        }
    }

    /// Retiring a document must not deliver coordinates into its replacement.
    func cancel() {
        completion = nil
        timeout?.cancel()
        timeout = nil
        manager.stopUpdatingLocation()
        requestingPosition = false
    }

    private func handleAuthorization() {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestingPosition else { return }
            requestingPosition = true
            manager.startUpdatingLocation()
        case .denied, .restricted:
            finish(["error": "permissionDenied"])
        case .notDetermined:
            break
        @unknown default:
            finish(["error": "unavailable"])
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        handleAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last,
              location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= 30,
              CLLocationCoordinate2DIsValid(location.coordinate) else { return }
        // Permission alerts can leave the app briefly inactive. Only actual
        // backgrounding cancels the request (via the observer above).
        finish(["lat": location.coordinate.latitude, "long": location.coordinate.longitude])
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A temporarily unavailable fix can recover before our timeout.
        if (error as? CLError)?.code == .locationUnknown { return }
        finish(["error": (error as? CLError)?.code == .denied ? "permissionDenied" : "unavailable"])
    }

    private func finish(_ fields: [String: Any]) {
        let callback = completion
        cancel()
        callback?(fields)
    }
}
