import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

/// Fixing a shift that was left running.
@MainActor
struct ShiftTimesTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ hours: Double) -> Date { t0.addingTimeInterval(hours * 3600) }

    private func setUp() throws -> (ShiftManager, ModelContext) {
        let schema = Schema([Trip.self, TripPoint.self, Shift.self, Payout.self, TaxPayment.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        return (ShiftManager(context: context), context)
    }

    private func trip(_ start: Double, _ end: Double, in context: ModelContext, shift: Shift? = nil, purpose: TripPurpose? = nil) -> Trip {
        let trip = Trip(startedAt: at(start), trigger: .motion)
        trip.endedAt = at(end)
        context.insert(trip)
        trip.shift = shift
        trip.purpose = purpose
        return trip
    }

    /// A shift left running overnight: worked 0–7 h, a stray drive at 9 h, ended at 23.5 h.
    private func leftRunning(_ manager: ShiftManager, _ context: ModelContext) -> (Shift, work: Trip, stray: Trip) {
        let shift = Shift(startedAt: at(0))
        context.insert(shift)
        shift.endedAt = at(23.5)
        manager.addPayout(20, platform: .spark, receivedAt: at(6.3), to: shift)
        let work = trip(5.8, 6.9, in: context, shift: shift, purpose: .business)
        let stray = trip(9.3, 9.7, in: context, shift: shift, purpose: .business)
        return (shift, work, stray)
    }

    @Test func endingEarlierSendsLaterTripsToReview() throws {
        let (manager, context) = try setUp()
        let (shift, work, stray) = leftRunning(manager, context)
        manager.updateTimes(of: shift, start: at(0), end: at(6.9))
        #expect(shift.endedAt == at(6.9))
        #expect(work.shift == shift && work.purpose == .business)
        #expect(stray.shift == nil && stray.purpose == nil)
        #expect(abs(shift.snapshot().duration - 6.9 * 3600) < 1)
    }

    @Test func aTripCrossingTheNewEndStays() throws {
        let (manager, context) = try setUp()
        let (shift, work, _) = leftRunning(manager, context)
        manager.updateTimes(of: shift, start: at(0), end: at(6.5))
        #expect(work.shift == shift)
    }

    @Test func startingEarlierPicksUpUnclaimedTripsButNotPersonalOnes() throws {
        let (manager, context) = try setUp()
        let (shift, _, _) = leftRunning(manager, context)
        manager.updateTimes(of: shift, start: at(1), end: at(7))
        let unclaimed = trip(0.2, 0.6, in: context)
        let personal = trip(0.3, 0.5, in: context, purpose: .personal)
        manager.updateTimes(of: shift, start: at(0), end: at(7))
        #expect(unclaimed.shift == shift && unclaimed.purpose == .business)
        #expect(personal.shift == nil && personal.purpose == .personal)
    }

    @Test func timesCantDropAPayoutOrOverlapAnotherShift() throws {
        let (manager, context) = try setUp()
        let earlier = Shift(startedAt: at(-3))
        context.insert(earlier)
        earlier.endedAt = at(-0.2)
        let (shift, _, _) = leftRunning(manager, context)
        let allowed = manager.allowedTimes(for: shift, now: at(30))
        #expect(allowed.start.lowerBound == at(-0.2))
        #expect(allowed.start.upperBound == at(6.3))
        #expect(allowed.end.lowerBound == at(6.3))
        #expect(allowed.end.upperBound == at(30))
    }

    @Test func crossedBoundsNeverTrap() {
        let range = Date.safeRange(at(5), at(2))
        #expect(range.lowerBound == at(2) && range.upperBound == at(2))
    }

    @Test func quickPicksAreTheLastPayoutAndTheDriveAfterIt() throws {
        let (manager, context) = try setUp()
        let (shift, _, _) = leftRunning(manager, context)
        let picks = EditShiftTimesView.endSuggestions(for: shift).map(\.date)
        #expect(picks == [at(6.3), at(6.9)])
    }

    @Test func endingTheActiveShiftEarlierDetachesLaterTrips() throws {
        let (manager, context) = try setUp()
        manager.startShift(at: at(0))
        let shift = try #require(manager.activeShift)
        manager.addPayout(20, platform: .spark, receivedAt: at(2), to: shift)
        let late = trip(4, 4.5, in: context, shift: shift, purpose: .business)
        manager.endShift(at: at(3))
        #expect(late.shift == nil && late.purpose == nil)
    }
}
