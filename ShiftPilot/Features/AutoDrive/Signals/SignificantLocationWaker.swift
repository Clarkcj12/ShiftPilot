import CoreLocation

/// Keeps significant-location-change monitoring on so iOS wakes, or relaunches, the
/// app after it moves roughly 500 m. That gives the route and motion monitors a
/// chance to notice a drive that started while ShiftPilot was suspended or terminated.
@MainActor
final class SignificantLocationWaker: NSObject {
    var onWake: (() -> Void)?

    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        startIfAuthorized()
    }

    private func startIfAuthorized() {
        guard manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
    }
}

extension SignificantLocationWaker: @preconcurrency CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        startIfAuthorized()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Log.location.info("Woken by significant location change")
        onWake?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        Log.location.error("Significant change monitoring failed: \(error.localizedDescription)")
    }
}
