import CoreLocation
import SwiftData

/// Writes trips to SwiftData.
///
/// A provisional trip (motion-only candidate) is buffered in memory and only
/// inserted on `confirm()`, so false starts never reach the store.
@MainActor
final class TripRecorder {
    private let context: ModelContext
    private let currentShift: @MainActor () -> Shift?
    private var pending: (startedAt: Date, trigger: TripTrigger)?
    private var buffer: [(location: CLLocation, delta: Double)] = []
    private var trip: Trip?
    private var unsavedPoints = 0

    private let saveEvery = 20

    /// - Parameter currentShift: the shift a newly confirmed trip should belong to.
    init(context: ModelContext, currentShift: @escaping @MainActor () -> Shift? = { nil }) {
        self.context = context
        self.currentShift = currentShift
    }

    func begin(trigger: TripTrigger, at date: Date) {
        pending = (date, trigger)
        buffer = []
        trip = nil
    }

    func record(_ location: CLLocation, distanceDelta: Double) {
        guard let trip else {
            buffer.append((location, distanceDelta))
            return
        }
        insertPoint(location, distanceDelta: distanceDelta, into: trip)
        unsavedPoints += 1
        if unsavedPoints >= saveEvery {
            save()
        }
    }

    func confirm() {
        guard trip == nil, let pending else { return }
        let trip = Trip(startedAt: pending.startedAt, trigger: pending.trigger)
        context.insert(trip)
        if let shift = currentShift() {
            trip.shift = shift
            trip.purpose = .business
        }
        for (location, delta) in buffer {
            insertPoint(location, distanceDelta: delta, into: trip)
        }
        buffer = []
        self.trip = trip
        save()
    }

    func finish(at date: Date) {
        if let trip {
            trip.endedAt = trip.points.map(\.timestamp).max() ?? date
            save()
        }
        reset()
    }

    func discard() {
        if let trip {
            context.delete(trip)
            save()
        }
        reset()
    }

    /// Closes trips left open when the app was terminated mid-drive.
    func closeAbandonedTrips() {
        let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt == nil })
        guard let open = try? context.fetch(descriptor), !open.isEmpty else { return }
        for trip in open {
            trip.endedAt = trip.points.map(\.timestamp).max() ?? trip.startedAt
        }
        Log.persistence.info("Closed \(open.count) abandoned trip(s)")
        save()
    }

    private func insertPoint(_ location: CLLocation, distanceDelta: Double, into trip: Trip) {
        let point = TripPoint(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            speed: location.speed,
            horizontalAccuracy: location.horizontalAccuracy
        )
        context.insert(point)
        point.trip = trip
        trip.distanceMeters += distanceDelta
    }

    private func save() {
        do {
            try context.save()
            unsavedPoints = 0
        } catch {
            Log.persistence.error("Save failed: \(error.localizedDescription)")
        }
    }

    private func reset() {
        pending = nil
        buffer = []
        trip = nil
        unsavedPoints = 0
    }
}
