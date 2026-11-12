import Foundation
import Observation
import SwiftData

/// Starts and ends shifts and records payouts.
@MainActor
@Observable
final class ShiftManager {
    private(set) var activeShift: Shift? {
        didSet {
            if (oldValue == nil) != (activeShift == nil) {
                onActiveShiftChange?(activeShift != nil)
            }
        }
    }

    /// Called when a shift starts or stops being active.
    @ObservationIgnored var onActiveShiftChange: (@MainActor (Bool) -> Void)?

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
            if trip.purpose == nil {
                trip.purpose = .business
            }
        }

        activeShift = shift
        Log.persistence.info("Shift started")
        save()
    }

    /// Ends the active shift. Refused (returns false) until the shift has at least one
    /// payout, so every saved shift says which app paid and how much.
    @discardableResult
    func endShift(at date: Date = .now) -> Bool {
        guard let activeShift, Self.canEnd(activeShift) else { return false }
        activeShift.endedAt = max(date, activeShift.startedAt)
        Self.reconcileTrips(of: activeShift, allTrips: activeShift.trips, now: date)
        self.activeShift = nil
        Log.persistence.info("Shift ended")
        save()
        return true
    }

    /// Moves a finished shift's start and end, for one left running by mistake or started late.
    /// Trips that no longer overlap it go back to Review; unclaimed trips inside it join it.
    func updateTimes(of shift: Shift, start: Date, end: Date) {
        guard !shift.isActive, start < end else { return }
        shift.startedAt = start
        shift.endedAt = end
        Self.reconcileTrips(of: shift, allTrips: allTrips(), now: .now)
        save()
    }

    /// The times a finished shift can move between: it can't overlap a neighbouring shift,
    /// end in the future, or leave out one of its payouts.
    func allowedTimes(for shift: Shift, now: Date = .now) -> (start: ClosedRange<Date>, end: ClosedRange<Date>) {
        let others = ((try? context.fetch(FetchDescriptor<Shift>())) ?? []).filter { $0 != shift }
        return Self.allowedTimes(for: shift, others: others, now: now)
    }

    static func allowedTimes(for shift: Shift, others: [Shift], now: Date) -> (start: ClosedRange<Date>, end: ClosedRange<Date>) {
        let start = shift.startedAt
        let previousEnd = others.compactMap(\.endedAt).filter { $0 <= start }.max() ?? .distantPast
        let nextStart = others.map(\.startedAt).filter { $0 >= start }.min() ?? .distantFuture
        let receipts = shift.payouts.map(\.receivedAt)
        let firstPayout = receipts.min() ?? now
        let lastPayout = receipts.max() ?? start
        return (
            start: Date.safeRange(previousEnd, min(firstPayout, now)),
            end: Date.safeRange(lastPayout, min(nextStart, now))
        )
    }

    /// Keeps a shift's trips in step with its times. A trip that no longer overlaps leaves the
    /// shift and goes back to Review; a trip with no shift that falls inside joins it as work.
    /// Personal trips are never pulled in.
    static func reconcileTrips(of shift: Shift, allTrips: [Trip], now: Date) {
        let start = shift.startedAt
        let end = shift.endedAt ?? now
        for trip in allTrips {
            let tripEnd = trip.endedAt ?? now
            let overlaps = trip.startedAt < end && tripEnd > start
            if trip.shift == shift, !overlaps {
                trip.shift = nil
                if trip.purpose == .business { trip.purpose = nil }
            } else if trip.shift == nil, trip.purpose != .personal, trip.startedAt >= start, tripEnd <= end {
                trip.shift = shift
                trip.purpose = .business
            }
        }
    }

    private func allTrips() -> [Trip] {
        (try? context.fetch(FetchDescriptor<Trip>())) ?? []
    }

    static func canEnd(_ shift: Shift) -> Bool {
        !shift.payouts.isEmpty
    }

    /// An ended shift must keep at least one payout.
    static func canDelete(_ payout: Payout) -> Bool {
        guard let shift = payout.shift, !shift.isActive else { return true }
        return shift.payouts.count > 1
    }

    func addPayout(_ amount: Decimal, platform: GigPlatform, receivedAt: Date, note: String = "", tip: Decimal? = nil, to shift: Shift) {
        let payout = Payout(amount: amount, platform: platform, receivedAt: receivedAt, note: note, tip: tip)
        context.insert(payout)
        payout.shift = shift
        save()
    }

    func updatePayout(_ payout: Payout, amount: Decimal, platform: GigPlatform, receivedAt: Date, note: String, tip: Decimal?) {
        payout.amount = amount
        payout.tip = tip
        payout.platformRawValue = platform.rawValue
        payout.receivedAt = receivedAt
        payout.note = note
        save()
    }

    func deletePayout(_ payout: Payout) {
        guard Self.canDelete(payout) else { return }
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

extension Date {
    /// `lower...upper`, or a single instant if the bounds cross, so a DatePicker range never traps.
    static func safeRange(_ lower: Date, _ upper: Date) -> ClosedRange<Date> {
        min(lower, upper)...upper
    }
}
