import SwiftData

/// Classifying and deleting finished trips.
@MainActor
enum TripEditor {
    /// A trip still being recorded can't be deleted; end it first.
    static func canDelete(_ trip: Trip) -> Bool {
        !trip.isActive
    }

    static func delete(_ trip: Trip, in context: ModelContext) {
        guard canDelete(trip) else { return }
        context.delete(trip)
        save(context)
    }

    static func setPurpose(_ purpose: TripPurpose, for trip: Trip, in context: ModelContext) {
        trip.purpose = purpose
        save(context)
    }

    private static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Trip save failed: \(error.localizedDescription)")
        }
    }
}
