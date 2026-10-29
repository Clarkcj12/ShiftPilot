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
///
/// During a shift the tracker stands by: GPS stays on between trips, which keeps the app
/// from being suspended (so CarPlay and speed are seen at once), and the last few minutes
/// of fixes are kept so a new trip is backfilled from where the car was last parked.
@MainActor
@Observable
final class MileageTracker: NSObject, TripTracking {
    private(set) var isTracking = false
    private(set) var isConfirmed = false
    private(set) var isStandingBy = false
    private(set) var distanceMeters: Double = 0

    var miles: Double { distanceMeters / 1609.344 }

    @ObservationIgnored var onSpeed: (@MainActor (Double) -> Void)?
    @ObservationIgnored private let recorder: TripRecorder
    @ObservationIgnored private let manager: CLLocationManager
    @ObservationIgnored private var lastAccepted: CLLocation?
    /// Fixes seen while standing by, newest last, trimmed to `standbyWindow`.
    @ObservationIgnored private var standbyFixes: [CLLocation] = []
    /// Replayed standby fixes are distance only; they aren't live speed readings.
    @ObservationIgnored private var isBackfilling = false

    /// Readings worse than this are dropped.
    private let maxHorizontalAccuracy: CLLocationDistance = 50
    /// Implied speeds above this (~155 mph) are GPS glitches.
    private let maxPlausibleSpeed: CLLocationSpeed = 70
    /// Points closer than this to the last accepted point are skipped (GPS jitter while slow or parked).
    private let minStep: CLLocationDistance = 10
    /// How far back standby fixes are kept for backfilling a trip's start.
    private let standbyWindow: TimeInterval = 180
    /// A backfill starts from the last fix at or below this (~5.6 mph), above walking pace,
    /// so the walk back to the car isn't counted as driving.
    private let backfillStartSpeed: CLLocationSpeed = 2.5

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
        let backfill = Self.backfill(standbyFixes, startSpeed: backfillStartSpeed)
        standbyFixes = []
        recorder.begin(trigger: trigger, at: backfill.first?.timestamp ?? .now)
        isBackfilling = true
        backfill.forEach(ingest)
        isBackfilling = false
        startUpdates()
    }

    func setStandby(_ isOn: Bool) {
        guard isOn != isStandingBy else { return }
        isStandingBy = isOn
        standbyFixes = []
        if isOn {
            startUpdates()
        } else if !isTracking {
            stopManager()
        }
    }

    /// The fixes since the car last pulled away (from the last fix at or below `startSpeed`
    /// on), or all of them if it was never that slow within the window.
    static func backfill(_ fixes: [CLLocation], startSpeed: CLLocationSpeed) -> [CLLocation] {
        guard let lastParked = fixes.lastIndex(where: { $0.speed >= 0 && $0.speed <= startSpeed }) else { return fixes }
        return Array(fixes[lastParked...])
    }

    private func startUpdates() {
        // Requires the `location` background mode; set here, not in init, so it's only on
        // during trips and shifts.
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    private func stopManager() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    private func standBy(with location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maxHorizontalAccuracy else { return }
        standbyFixes.append(location)
        standbyFixes.removeAll { location.timestamp.timeIntervalSince($0.timestamp) > standbyWindow }
        if location.speed >= 0 { onSpeed?(location.speed) }
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
            if location.speed >= 0, !isBackfilling { onSpeed?(location.speed) }
            accept(location, delta: 0)
            return
        }

        let delta = location.distance(from: last)
        let elapsed = location.timestamp.timeIntervalSince(last.timestamp)
        guard elapsed > 0 else { return }
        let impliedSpeed = delta / elapsed
        guard impliedSpeed <= maxPlausibleSpeed else { return }

        if !isBackfilling {
            onSpeed?(location.speed >= 0 ? location.speed : impliedSpeed)
        }

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
        if !isStandingBy {
            stopManager()
        }
        isTracking = false
        isConfirmed = false
        lastAccepted = nil
    }
}

extension MileageTracker: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if isTracking {
            locations.forEach(ingest)
        } else if isStandingBy {
            locations.forEach(standBy)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        // `.locationUnknown` is transient; the manager keeps trying.
        if (error as? CLError)?.code == .locationUnknown { return }
        Log.location.error("Location updates failed: \(error.localizedDescription)")
    }
}
