import CoreMotion

/// Fallback drive trigger for cars with no Bluetooth/CarPlay: the motion coprocessor's
/// `automotive` activity.
@MainActor
final class MotionActivityMonitor: DriveSignalSource {
    private let manager = CMMotionActivityManager()
    private var continuation: AsyncStream<DriveSignal>.Continuation?

    func start() -> AsyncStream<DriveSignal> {
        let (stream, continuation) = AsyncStream.makeStream(of: DriveSignal.self)
        self.continuation = continuation

        guard CMMotionActivityManager.isActivityAvailable() else {
            Log.autodrive.notice("Motion activity unavailable on this device")
            continuation.finish()
            return stream
        }

        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            continuation.yield(.motion(MotionReading(activity)))
        }
        refresh()
        return stream
    }

    /// Catches up on a drive that began while the app was suspended or terminated.
    func refresh() {
        guard let continuation, CMMotionActivityManager.isActivityAvailable() else { return }
        let now = Date.now
        manager.queryActivityStarting(from: now.addingTimeInterval(-120), to: now, to: .main) { activities, _ in
            guard let latest = activities?.last else { return }
            continuation.yield(.motion(MotionReading(latest)))
        }
    }

    func stop() {
        manager.stopActivityUpdates()
        continuation?.finish()
        continuation = nil
    }
}

extension MotionReading {
    init(_ activity: CMMotionActivity) {
        let confidence: Confidence = switch activity.confidence {
        case .high: .high
        case .medium: .medium
        default: .low
        }
        self.init(isAutomotive: activity.automotive, confidence: confidence)
    }
}
