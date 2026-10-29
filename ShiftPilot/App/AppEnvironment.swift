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
    let garage: GarageStore

    private let recorder: TripRecorder
    private let waker = SignificantLocationWaker()

    init() {
        do {
            modelContainer = try ModelContainer(for: Trip.self, TripPoint.self, Shift.self, Payout.self, TaxPayment.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self)
        } catch {
            fatalError("Could not create the trip store: \(error)")
        }

        permissions = PermissionsManager()
        knownDevices = KnownDevicesStore()
        bleMonitor = BLEAccessoryMonitor(devices: knownDevices)
        let shifts = ShiftManager(context: modelContainer.mainContext)
        self.shifts = shifts
        let garage = GarageStore(context: modelContainer.mainContext)
        self.garage = garage
        recorder = TripRecorder(
            context: modelContainer.mainContext,
            currentShift: { shifts.activeShift },
            currentVehicle: { garage.current }
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
        #if DEBUG
        if SampleData.isRequested {
            SampleData.seedIfEmpty(modelContainer.mainContext, garage: garage)
        }
        #endif
        recorder.closeAbandonedTrips()
        waker.start()
        autoDrive.start()
    }
}
