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
    let shifts: ShiftManager
    let vehicle: VehicleStore

    private let recorder: TripRecorder
    private let waker = SignificantLocationWaker()

    init() {
        do {
            modelContainer = try ModelContainer(for: Trip.self, TripPoint.self, Shift.self, Payout.self, TaxPayment.self)
        } catch {
            fatalError("Could not create the trip store: \(error)")
        }

        permissions = PermissionsManager()
        knownDevices = KnownDevicesStore()
        bleMonitor = BLEAccessoryMonitor(devices: knownDevices)
        let shifts = ShiftManager(context: modelContainer.mainContext)
        self.shifts = shifts
        let vehicle = VehicleStore()
        self.vehicle = vehicle
        recorder = TripRecorder(
            context: modelContainer.mainContext,
            currentShift: { shifts.activeShift },
            costPerMeter: { vehicle.costPerMeter }
        )
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
