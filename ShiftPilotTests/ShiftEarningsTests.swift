import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// 2026-01-05 at the given UTC hour and minute.
private func date(_ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: hour, minute: minute))!
}

private func payout(_ platform: GigPlatform, _ amount: Decimal, at hour: Int, _ minute: Int = 0) -> PayoutSnapshot {
    PayoutSnapshot(platform: platform, amount: amount, receivedAt: date(hour, minute))
}

struct EarningsCalculatorTests {
    @Test func trueEPHUsesWholeShiftDuration() {
        let shift = ShiftSnapshot(
            start: date(17), end: date(19, 30),
            payouts: [payout(.doorDash, 30, at: 18), payout(.doorDash, 20, at: 19)],
            distanceMeters: 0
        )
        #expect(shift.gross == 50)
        #expect(shift.hourlyRate == 20)
    }

    @Test func noRateForTinyShifts() {
        let shift = ShiftSnapshot(start: date(17), end: date(17).addingTimeInterval(30), payouts: [payout(.uber, 5, at: 17)], distanceMeters: 0)
        #expect(shift.hourlyRate == nil)
    }

    @Test func earningsPerDistance() {
        let shift = ShiftSnapshot(start: date(17), end: date(18), payouts: [payout(.lyft, 25, at: 17, 30)], distanceMeters: 10_000)
        #expect(shift.earningsPerDistance(in: .kilometers) == Decimal(2.5))
        #expect(ShiftSnapshot(start: date(17), end: date(18), payouts: [], distanceMeters: 10).earningsPerDistance(in: .kilometers) == nil)
    }

    @Test func multiAppShiftCountsFullTimeForEachPlatform() {
        let shifts = [
            ShiftSnapshot(start: date(17), end: date(19), payouts: [payout(.doorDash, 40, at: 18), payout(.uberEats, 20, at: 18)], distanceMeters: 0),
            ShiftSnapshot(start: date(11), end: date(12), payouts: [payout(.uberEats, 30, at: 11, 30)], distanceMeters: 0),
        ]
        let rows = EarningsCalculator.byPlatform(shifts)
        #expect(rows.map(\.key) == [.doorDash, .uberEats])
        #expect(rows[0].hourlyRate == 20)          // $40 over 2h
        #expect(rows[1].gross == 50)
        #expect(rows[1].seconds == 3 * 3600)       // 2h + 1h
    }

    @Test func secondsSplitAcrossHoursAndMidnight() {
        let start = date(23, 30)
        let end = start.addingTimeInterval(90 * 60)
        let split = EarningsCalculator.secondsByHourOfDay(from: start, to: end, calendar: utc)
        #expect(split == [23: 1800, 0: 3600])
    }

    @Test func daypartsSplitShiftTimeAndBucketPayoutsByTime() {
        let shift = ShiftSnapshot(
            start: date(16), end: date(18),
            payouts: [payout(.doorDash, 10, at: 16, 30), payout(.doorDash, 30, at: 17, 30)],
            distanceMeters: 0
        )
        let rows = EarningsCalculator.byDaypart([shift], calendar: utc)
        #expect(rows.map(\.key) == [.afternoon, .dinner])
        #expect(rows[0].hourlyRate == 10)
        #expect(rows[1].hourlyRate == 30)
    }

    @Test func daypartBoundaries() {
        #expect(Daypart(hour: 4) == .lateNight)
        #expect(Daypart(hour: 5) == .breakfast)
        #expect(Daypart(hour: 13) == .lunch)
        #expect(Daypart(hour: 17) == .dinner)
        #expect(Daypart(hour: 21) == .lateNight)
    }
}

@MainActor
struct ShiftManagerTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Trip.self, TripPoint.self, Shift.self, Payout.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func confirmedTripsJoinTheActiveShift() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        let recorder = TripRecorder(context: context) { shifts.activeShift }

        shifts.startShift()
        recorder.begin(trigger: .carPlay, at: .now)
        recorder.confirm()
        recorder.finish(at: .now)

        let shift = try #require(shifts.activeShift)
        #expect(shift.trips.count == 1)

        shifts.addPayout(9, platform: .shipt, receivedAt: .now, to: shift)
        #expect(shifts.endShift())
        #expect(shifts.activeShift == nil)
        #expect(shift.endedAt != nil)
    }

    @Test func tinyGPSTripIsDroppedButRealOneKept() throws {
        let context = try makeContext()
        let recorder = TripRecorder(context: context)
        func drive(_ meters: Double, trigger: TripTrigger) {
            recorder.begin(trigger: trigger, at: .now)
            recorder.confirm()
            recorder.record(CLLocation(latitude: 38.3, longitude: -76.5), distanceDelta: meters)
            recorder.finish(at: .now)
        }
        drive(40, trigger: .gps)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 0)
        drive(400, trigger: .gps)
        drive(40, trigger: .carPlay)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 2)
    }

    @Test func startingAShiftAdoptsTheTripInProgress() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        let recorder = TripRecorder(context: context) { shifts.activeShift }

        recorder.begin(trigger: .manual, at: .now)
        recorder.confirm()
        shifts.startShift()

        #expect(shifts.activeShift?.trips.count == 1)
    }

    @Test func activeShiftSurvivesRelaunch() throws {
        let context = try makeContext()
        ShiftManager(context: context).startShift()
        #expect(ShiftManager(context: context).activeShift != nil)
    }

    @Test func payoutsAddUpOnTheShift() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift(at: .now.addingTimeInterval(-3600))
        let shift = try #require(shifts.activeShift)

        shifts.addPayout(12.5, platform: .doorDash, receivedAt: .now, to: shift)
        shifts.addPayout(7.5, platform: .uber, receivedAt: .now, to: shift)
        #expect(shift.snapshot().gross == 20)

        shifts.deletePayout(shift.payouts[0])
        #expect(shift.payouts.count == 1)
    }

    @Test func shiftWithoutPayoutCannotEnd() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift()
        let shift = try #require(shifts.activeShift)

        #expect(!shifts.endShift())
        #expect(shifts.activeShift === shift)
        #expect(shift.endedAt == nil)

        shifts.addPayout(15, platform: .instacart, receivedAt: .now, to: shift)
        #expect(shifts.endShift())
        #expect(shift.endedAt != nil)
    }

    @Test func endedShiftKeepsItsLastPayout() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift()
        let shift = try #require(shifts.activeShift)
        shifts.addPayout(15, platform: .instacart, receivedAt: .now, to: shift)
        shifts.endShift()

        shifts.deletePayout(shift.payouts[0])
        #expect(shift.payouts.count == 1)
    }

    // MARK: Trip purpose

    @Test func tripsConfirmedOnShiftAreBusiness() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        let recorder = TripRecorder(context: context) { shifts.activeShift }

        recorder.begin(trigger: .motion, at: .now)
        recorder.confirm()
        recorder.finish(at: .now)

        shifts.startShift()
        recorder.begin(trigger: .carPlay, at: .now)
        recorder.confirm()
        recorder.finish(at: .now)

        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(trips.map(\.purpose) == [nil, .business])
    }

    @Test func tripAdoptedByNewShiftIsBusiness() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        let recorder = TripRecorder(context: context) { shifts.activeShift }

        recorder.begin(trigger: .manual, at: .now)
        recorder.confirm()
        shifts.startShift()

        #expect(shifts.activeShift?.trips.first?.purpose == .business)
    }

    @Test func personalTripsDontCountTowardShiftDistance() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift()
        let shift = try #require(shifts.activeShift)

        let work = Trip(startedAt: .now, trigger: .carPlay)
        work.distanceMeters = 5000
        let errand = Trip(startedAt: .now, trigger: .carPlay)
        errand.distanceMeters = 2000
        for trip in [work, errand] {
            context.insert(trip)
            trip.shift = shift
            trip.purpose = .business
        }
        #expect(shift.snapshot().distanceMeters == 7000)

        TripEditor.setPurpose(.personal, for: errand, in: context)
        #expect(shift.snapshot().distanceMeters == 5000)
    }

    @Test func activeTripCannotBeDeleted() throws {
        let context = try makeContext()
        let trip = Trip(startedAt: .now, trigger: .manual)
        context.insert(trip)

        TripEditor.delete(trip, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 1)

        trip.endedAt = .now
        TripEditor.delete(trip, in: context)
        #expect(try context.fetchCount(FetchDescriptor<Trip>()) == 0)
    }

    @Test func payoutCanBeEdited() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift()
        let shift = try #require(shifts.activeShift)
        shifts.addPayout(12, platform: .doorDash, receivedAt: .now, to: shift)

        shifts.updatePayout(shift.payouts[0], amount: 21, platform: .shipt, receivedAt: .now, note: "Typo")
        #expect(shift.payouts[0].amount == 21)
        #expect(shift.payouts[0].platform == .shipt)
    }
}
