import Foundation
import Observation

/// What the detection manager needs from the mileage layer.
@MainActor
protocol TripTracking: AnyObject {
    /// Called with each GPS speed sample (m/s) while tracking.
    var onSpeed: (@MainActor (Double) -> Void)? { get set }
    func beginTrip(trigger: TripTrigger)
    func confirmTrip()
    func finishTrip()
    func discardTrip()
}

/// Merges car-connection, motion and speed signals and starts/stops GPS mileage tracking.
///
/// The decision logic lives in `DriveDetector.reduce`; this class only wires
/// signal sources and a timer into it and forwards the resulting effects.
@MainActor
@Observable
final class AutoDriveDetectionManager {
    private(set) var state = DetectorState()
    private(set) var isRunning = false

    @ObservationIgnored private let sources: [any DriveSignalSource]
    @ObservationIgnored private let tracker: any TripTracking
    @ObservationIgnored private let config: DetectionConfig
    @ObservationIgnored private let tickInterval: Duration
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(
        sources: [any DriveSignalSource],
        tracker: any TripTracking,
        config: DetectionConfig = DetectionConfig(),
        tickInterval: Duration = .seconds(15),
        now: @escaping () -> Date = Date.init
    ) {
        self.sources = sources
        self.tracker = tracker
        self.config = config
        self.tickInterval = tickInterval
        self.now = now
        tracker.onSpeed = { [weak self] speed in
            self?.handle(.speed(metersPerSecond: speed))
        }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Log.autodrive.info("Auto-Drive detection started")

        for source in sources {
            let stream = source.start()
            tasks.append(Task { [weak self] in
                for await signal in stream {
                    self?.handle(signal)
                }
            })
        }

        tasks.append(Task { [weak self, tickInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: tickInterval)
                guard let self else { return }
                self.handle(.tick)
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        sources.forEach { $0.stop() }
        isRunning = false
    }

    /// Asks every source to re-read current state (called when iOS wakes the app).
    func refresh() {
        sources.forEach { $0.refresh() }
    }

    func startTripManually() {
        handle(.manualStart)
    }

    func endTripManually() {
        handle(.manualStop)
    }

    func handle(_ signal: DriveSignal) {
        let previous = state.phase
        let effects = DriveDetector.reduce(&state, signal, at: now(), config: config)
        if state.phase != previous {
            Log.autodrive.info("Phase \(String(describing: previous)) → \(String(describing: self.state.phase)) on \(String(describing: signal))")
        }
        effects.forEach(perform)
    }

    private func perform(_ effect: DetectorEffect) {
        switch effect {
        case .beginTrip(let trigger): tracker.beginTrip(trigger: trigger)
        case .confirmTrip: tracker.confirmTrip()
        case .finishTrip: tracker.finishTrip()
        case .discardTrip: tracker.discardTrip()
        }
    }
}
