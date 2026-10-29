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
    /// A candidate whose GPS shows the phone parked is discarded after this long.
    var candidateStillTimeout: TimeInterval = 60
    /// At or below this speed the car counts as parked (~2 mph).
    var stationarySpeed: Double = 0.9
    /// How long the car must be parked, with no car signal, before the trip ends.
    var endDuration: TimeInterval = 180
}

/// Where a trip's detection came from; stored on the trip.
enum TripTrigger: String, Sendable, Codable {
    case carPlay, bluetoothAudio, bleAccessory, motion, manual
    /// Driving speed seen on GPS during a shift.
    case gps

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
    /// Set when a motion candidate is discarded; motion must report non-automotive
    /// before it can start another, so a stuck automotive reading can't loop.
    var motionNeedsReset = false
    /// A shift is running, so GPS is on between trips and feeds `.speed` while idle.
    var isOnShift = false
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
///     idle ──on shift, GPS at driving speed─────────▶ driving
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
            if !state.isAutomotive {
                state.motionNeedsReset = false
            }
            let canStartCandidate = state.isAutomotive && !reading.isStationary
                && !state.suppressAutoStart && !state.motionNeedsReset
            switch state.phase {
            case .idle where canStartCandidate:
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
                state.stillSince = speed <= config.stationarySpeed ? (state.stillSince ?? now) : nil
            case .driving, .ending:
                state.stillSince = speed <= config.stationarySpeed ? (state.stillSince ?? now) : nil
            case .idle where state.isOnShift && speed >= config.drivingSpeed && !state.suppressAutoStart:
                // On shift, driving speed on GPS is a drive: confirm at once. Stop-and-go
                // traffic rarely holds `confirmDuration`, and a discarded candidate loses
                // its miles. The recorder drops GPS trips too short to be real.
                effects = [.beginTrip(.gps), .confirmTrip]
                state.enterDriving()
            case .idle:
                break
            }

        case .shift(let isActive):
            state.isOnShift = isActive

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
            let timedOut = state.candidateSince.map { now.timeIntervalSince($0) >= config.candidateTimeout } ?? false
            let parked = state.stillSince.map { now.timeIntervalSince($0) >= config.candidateStillTimeout } ?? false
            if timedOut || parked {
                state.reset()
                state.motionNeedsReset = state.isAutomotive
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
