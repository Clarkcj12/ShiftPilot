import Foundation
import Observation
import SwiftData

/// Starts and ends shifts and records payouts.
@MainActor
@Observable
final class ShiftManager {
    private(set) var activeShift: Shift?

    @ObservationIgnored private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
        // Shifts deliberately survive app termination; pick up one that's still open.
        var descriptor = FetchDescriptor<Shift>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        activeShift = try? context.fetch(descriptor).first
    }

    func startShift(at date: Date = .now) {
        guard activeShift == nil else { return }
        let shift = Shift(startedAt: date)
        context.insert(shift)

        // A drive already in progress belongs to the new shift.
        let openTrips = (try? context.fetch(FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt == nil }))) ?? []
        for trip in openTrips where trip.shift == nil {
            trip.shift = shift
        }

        activeShift = shift
        Log.persistence.info("Shift started")
        save()
    }

    func endShift(at date: Date = .now) {
        guard let activeShift else { return }
        activeShift.endedAt = date
        self.activeShift = nil
        Log.persistence.info("Shift ended")
        save()
    }

    func addPayout(_ amount: Decimal, platform: GigPlatform, receivedAt: Date, note: String = "", to shift: Shift) {
        let payout = Payout(amount: amount, platform: platform, receivedAt: receivedAt, note: note)
        context.insert(payout)
        payout.shift = shift
        save()
    }

    func deletePayout(_ payout: Payout) {
        context.delete(payout)
        save()
    }

    func deleteShift(_ shift: Shift) {
        if shift == activeShift {
            activeShift = nil
        }
        context.delete(shift)
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Shift save failed: \(error.localizedDescription)")
        }
    }
}
