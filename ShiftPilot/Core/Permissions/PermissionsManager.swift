import CoreLocation
import CoreMotion
import Observation

/// Location and motion authorization. Bluetooth is requested lazily by
/// `BLEAccessoryMonitor` only when the user pairs an accessory.
@MainActor
@Observable
final class PermissionsManager: NSObject {
    private(set) var locationStatus: CLAuthorizationStatus
    private(set) var motionStatus: CMAuthorizationStatus

    @ObservationIgnored private let locationManager: CLLocationManager
    @ObservationIgnored private let motionManager = CMMotionActivityManager()

    override init() {
        let locationManager = CLLocationManager()
        self.locationManager = locationManager
        locationStatus = locationManager.authorizationStatus
        motionStatus = CMMotionActivityManager.authorizationStatus()
        super.init()
        locationManager.delegate = self
    }

    var hasAlwaysLocation: Bool { locationStatus == .authorizedAlways }
    var isFullyAuthorized: Bool { hasAlwaysLocation && motionStatus == .authorized }

    /// iOS requires When In Use first; a second call upgrades to Always.
    func requestLocation() {
        switch locationStatus {
        case .notDetermined: locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: locationManager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// CoreMotion has no explicit request API; the first query shows the prompt.
    func requestMotion() {
        let now = Date.now
        motionManager.queryActivityStarting(from: now, to: now, to: .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.motionStatus = CMMotionActivityManager.authorizationStatus()
            }
        }
    }
}

extension PermissionsManager: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        locationStatus = manager.authorizationStatus
    }
}
