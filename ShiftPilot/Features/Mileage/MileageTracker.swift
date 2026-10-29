import CoreLocation
import Observation

/// Background GPS tracking for a single trip.
///
/// Uses `CLLocationManager` with `allowsBackgroundLocationUpdates` rather than
/// `CLLocationUpdate.liveUpdates` + `CLBackgroundActivitySession`: trips usually
/// begin while ShiftPilot is in the background (woken by a CarPlay/Bluetooth route
/// change or a significant location change), and with Always authorization only the
/// manager-based API can start continuous updates from there. A background activity
/// session started in the background never delivers, which recorded 0-mile trips.
///
/// Points are filtered for accuracy and GPS jumps before being summed into the trip distance.
@MainActor
@Observable
final class MileageTracker: NSObject, TripTracking {
    private(set) var isTracking = false
    private(set) var isConfirmed = false
    private(set) var distanceMeters: Double = 0

    var miles: Double { distanceMeters / 1609.344 }

    @ObservationIgnored var onSpeed: (@MainActor (Double) -> Void)?
    @ObservationIgnored private let recorder: TripRecorder
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var lastAccepted: CLLocation?

    /// Readings worse than this are dropped.
    private let maxHorizontalAccuracy: CLLocationDistance = 50
    /// Implied speeds above this (~155 mph) are GPS glitches.
    private let maxPlausibleSpeed: CLLocationSpeed = 70
    /// Points closer than this to the last accepted point are skipped (GPS jitter while slow or parked).
    private let minStep: CLLocationDistance = 10

    init(recorder: TripRecorder) {
        self.recorder = recorder
        let manager = CLLocationManager()
        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.showsBackgroundLocationIndicator = true
        self.manager = manager
        super.init()
        manager.delegate = self
    }

    func beginTrip(trigger: TripTrigger) {
        guard !isTracking else { return }
        Log.location.info("Begin trip (\(trigger.rawValue))")
        isTracking = true
        isConfirmed = false
        distanceMeters = 0
        lastAccepted = nil
        recorder.begin(trigger: trigger, at: .now)

        // Requires the `location` background mode; set here, not in init, so it's only on during trips.
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    func confirmTrip() {
        guard isTracking else { return }
        isConfirmed = true
        recorder.confirm()
    }

    func finishTrip() {
        guard isTracking else { return }
        Log.location.info("Finish trip: \(self.miles, format: .fixed(precision: 2)) mi")
        stopUpdates()
        recorder.finish(at: .now)
    }

    func discardTrip() {
        guard isTracking else { return }
        Log.location.info("Discard provisional trip")
        stopUpdates()
        recorder.discard()
    }

    private func ingest(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxHorizontalAccuracy else { return }

        guard let last = lastAccepted else {
            if location.speed >= 0 { onSpeed?(location.speed) }
            accept(location, delta: 0)
            return
        }

        let delta = location.distance(from: last)
        let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
        guard elapsed > 0 else { return }
        let impliedSpeed = delta / elapsed
        guard impliedSpeed <= maxPlausibleSpeed else { return }

        onSpeed?(location.speed >= 0 ? location.speed : impliedSpeed)

        // `lastAccepted` only advances on accepted points, so skipped jitter isn't lost distance.
        guard delta >= max(minStep, location.horizontalAccuracy) else { return }
        accept(location, delta: delta)
    }

    private func accept(_ location: CLLocation, delta: CLLocationDistance) {
        lastAccepted = location
        distanceMeters += delta
        recorder.record(location, distanceDelta: delta)
    }

    private func stopUpdates() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
        isConfirmed = false
        lastAccepted = nil
    }
}

extension MileageTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isTracking else { return }
        locations.forEach(ingest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // `.locationUnknown` is transient; the manager keeps trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        Log.location.error("Location updates failed: \(error.localizedDescription)")
    }
}
