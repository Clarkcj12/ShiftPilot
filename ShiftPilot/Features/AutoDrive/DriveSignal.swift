import Foundation

/// A single observation fed into the Auto-Drive state machine.
enum DriveSignal: Sendable, Equatable {
    case carConnected(CarConnection)
    case carDisconnected(CarConnection)
    case motion(MotionReading)
    case speed(metersPerSecond: Double)
    /// The driver tapped Start trip.
    case manualStart
    /// The driver tapped End trip.
    case manualStop
    /// Emitted by the manager's timer so time-based transitions fire without new signals.
    case tick
}

/// Something that tells us the phone is in the car.
enum CarConnection: Sendable, Hashable {
    /// CarPlay (wired or wireless) — always a car.
    case carPlay
    /// Classic Bluetooth / LE audio device the user has marked as their car.
    case bluetoothAudio(uid: String, name: String)
    /// User-paired BLE accessory (e.g. an OBD-II dongle).
    case bleAccessory(UUID)
}

struct MotionReading: Sendable, Equatable {
    enum Confidence: Int, Sendable, Comparable {
        case low, medium, high

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var isAutomotive: Bool
    var confidence: Confidence
}

/// A producer of drive signals (audio route, motion, BLE).
@MainActor
protocol DriveSignalSource: AnyObject {
    /// Begins observing. The returned stream stays open until `stop()`.
    func start() -> AsyncStream<DriveSignal>
    /// Re-reads current state, e.g. after iOS wakes the app in the background.
    func refresh()
    func stop()
}
