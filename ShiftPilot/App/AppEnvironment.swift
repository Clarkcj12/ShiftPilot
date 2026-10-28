import SwiftData

/// Builds and owns the app's long-lived services.
@MainActor
final class AppEnvironment {
    let modelContainer: ModelContainer
    let permissions: PermissionsManager
    let knownDevices: KnownDevicesStore
    let bleMonitor: BLEAccessoryMonitor
    let tracker: MileageTracker
    let autoDrive: AutoDriveDetectionManager

    private let recorder: TripRecorder
    private let waker = SignificantLocationWaker()

    init() {
        do {
            modelContainer = try ModelContainer(for: Trip.self, TripPoint.self)
        } catch {
            fatalError("Could not create the trip store: \(error)")
        }

        permissions = PermissionsManager()
        knownDevices = KnownDevicesStore()
        bleMonitor = BLEAccessoryMonitor(devices: knownDevices)
        recorder = TripRecorder(context: modelContainer.mainContext)
        tracker = MileageTracker(recorder: recorder)
        autoDrive = AutoDriveDetectionManager(
            sources: [
                CarAudioRouteMonitor(devices: knownDevices),
                MotionActivityMonitor(),
                bleMonitor,
            ],
            tracker: tracker
        )
        waker.onWake = { [weak autoDrive] in autoDrive?.refresh() }
    }

    /// Called from `application(_:didFinishLaunchingWithOptions:)`, including background relaunches.
    func start() {
        recorder.closeAbandonedTrips()
        waker.start()
        autoDrive.start()
    }
}
