import Foundation

struct DetectionConfig: Sendable {
    /// Motion readings below this confidence are ignored.
    var minimumMotionConfidence: MotionReading.Confidence = .medium
    /// Speed a motion-only candidate must hold to become a trip (~15 mph).
    var drivingSpeed: Double = 6.7
    /// How long `drivingSpeed` must be held.
    var confirmDuration: TimeInterval = 60
    /// A candidate that never reaches driving speed is discarded after this long.
    var candidateTimeout: TimeInterval = 300
    /// At or below this speed the car counts as parked (~2 mph).
    var stationarySpeed: Double = 0.9
    /// How long the car must be parked, with no car signal, before the trip ends.
    var endDuration: TimeInterval = 180
}

/// Where a trip's detection came from; stored on the trip.
enum TripTrigger: String, Sendable, Codable {
    case carPlay, bluetoothAudio, bleAccessory, motion, manual

    init(_ connection: CarConnection) {
        switch connection {
        case .carPlay: self = .carPlay
        case .bluetoothAudio: self = .bluetoothAudio
        case .bleAccessory: self = .bleAccessory
        }
    }
}

struct DetectorState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// Not driving.
        case idle
        /// Motion says automotive; GPS is running to confirm with speed.
        case candidate
        /// Trip confirmed and recording.
        case driving
        /// Car signals are gone; waiting for the car to stay parked.
        case ending
    }

    var phase: Phase = .idle
    var connections: Set<CarConnection> = []
    var isAutomotive = false
    /// The current trip was started by the driver; only `manualStop` ends it.
    var isManual = false
    /// Set by `manualStop` so the car signals still present don't immediately
    /// restart a trip. Cleared once those signals go away.
    var suppressAutoStart = false
    var candidateSince: Date?
    var fastSince: Date?
    var stillSince: Date?

    /// True while the car or motion says we're in a moving car.
    var hasCarSignal: Bool { !connections.isEmpty || isAutomotive }
    /// True while something says the trip should continue.
    var hasActiveSignal: Bool { isManual || hasCarSignal }

    mutating func enterDriving() {
        phase = hasActiveSignal ? .driving : .ending
        candidateSince = nil
        fastSince = nil
        stillSince = nil
    }

    mutating func reset() {
        phase = .idle
        isManual = false
        candidateSince = nil
        fastSince = nil
        stillSince = nil
    }
}

enum DetectorEffect: Equatable, Sendable {
    /// Start GPS. The trip is provisional until `confirmTrip`.
    case beginTrip(TripTrigger)
    case confirmTrip
    case finishTrip
    case discardTrip
}

/// Pure state machine for Auto-Drive Detection.
///
///     idle ──car connected──────────────────────────▶ driving
///     idle ──automotive motion──▶ candidate ──speed held──▶ driving
///     candidate ──timeout──▶ idle (discard)
///     driving ──car + motion signals lost──▶ ending ──parked for endDuration──▶ idle (finish)
///     ending ──car reconnects / automotive again──▶ driving
///
/// Manual overrides: `manualStart` goes straight to driving, and that trip only ends
/// on `manualStop`. `manualStop` ends any trip and holds off auto-start until the
/// car and motion signals clear, so the still-connected car doesn't restart it.
enum DriveDetector {
    static func reduce(
        _ state: inout DetectorState,
        _ signal: DriveSignal,
        at now: Date,
        config: DetectionConfig
    ) -> [DetectorEffect] {
        var effects: [DetectorEffect] = []

        switch signal {
        case .carConnected(let connection):
            state.connections.insert(connection)
            switch state.phase {
            case .idle where state.suppressAutoStart:
                break
            case .idle:
                effects = [.beginTrip(TripTrigger(connection)), .confirmTrip]
                state.enterDriving()
            case .candidate:
                effects = [.confirmTrip]
                state.enterDriving()
            case .driving, .ending:
                state.enterDriving()
            }

        case .carDisconnected(let connection):
            state.connections.remove(connection)
            if state.phase == .driving, !state.hasActiveSignal {
                state.phase = .ending
            }

        case .motion(let reading):
            state.isAutomotive = reading.isAutomotive && reading.confidence >= config.minimumMotionConfidence
            switch state.phase {
            case .idle where state.isAutomotive && !state.suppressAutoStart:
                state.phase = .candidate
                state.candidateSince = now
                effects = [.beginTrip(.motion)]
            case .driving where !state.hasActiveSignal:
                state.phase = .ending
            case .ending where state.hasActiveSignal:
                state.phase = .driving
            default:
                break
            }

        case .speed(let speed):
            switch state.phase {
            case .candidate:
                state.fastSince = speed >= config.drivingSpeed ? (state.fastSince ?? now) : nil
            case .driving, .ending:
                state.stillSince = speed <= config.stationarySpeed ? (state.stillSince ?? now) : nil
            case .idle:
                break
            }

        case .manualStart:
            switch state.phase {
            case .idle: effects = [.beginTrip(.manual), .confirmTrip]
            case .candidate: effects = [.confirmTrip]
            case .driving, .ending: break
            }
            state.isManual = true
            state.suppressAutoStart = false
            state.enterDriving()

        case .manualStop:
            switch state.phase {
            case .idle: break
            case .candidate: effects = [.discardTrip]
            case .driving, .ending: effects = [.finishTrip]
            }
            state.reset()
            state.suppressAutoStart = state.hasCarSignal

        case .tick:
            break
        }

        if state.suppressAutoStart, !state.hasCarSignal {
            state.suppressAutoStart = false
        }

        return effects + evaluateTimers(&state, at: now, config: config)
    }

    private static func evaluateTimers(
        _ state: inout DetectorState,
        at now: Date,
        config: DetectionConfig
    ) -> [DetectorEffect] {
        switch state.phase {
        case .candidate:
            if let fastSince = state.fastSince, now.timeIntervalSince(fastSince) >= config.confirmDuration {
                state.enterDriving()
                return [.confirmTrip]
            }
            if let candidateSince = state.candidateSince, now.timeIntervalSince(candidateSince) >= config.candidateTimeout {
                state.reset()
                return [.discardTrip]
            }
        case .ending:
            if let stillSince = state.stillSince, now.timeIntervalSince(stillSince) >= config.endDuration {
                state.reset()
                return [.finishTrip]
            }
        case .idle, .driving:
            break
        }
        return []
    }
}
