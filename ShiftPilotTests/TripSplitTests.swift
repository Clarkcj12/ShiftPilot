import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

@MainActor
struct TripSplitTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A point `east` meters east of the start, `minutes` in.
    private func sample(_ minutes: Double, east: Double) -> TripEditor.Sample {
        TripEditor.Sample(timestamp: t0.addingTimeInterval(minutes * 60), latitude: 38.3, longitude: -76.5 + east / 87_350)
    }

    /// Drive 0–10 min (2 km), park 10–40 min with drift, drive 40–50 min (2 km more).
    private var drivingParkedDriving: [TripEditor.Sample] {
        var samples = (0...10).map { sample(Double($0), east: Double($0) * 200) }
        samples += stride(from: 12.0, through: 38, by: 2).map { sample($0, east: 2000 + ($0.truncatingRemainder(dividingBy: 4) == 0 ? 20 : -20)) }
        samples += (40...50).map { sample(Double($0), east: 2000 + Double($0 - 40) * 200) }
        return samples
    }

    @Test func findsTheLongStopButNotDriving() throws {
        let stops = TripEditor.stops(in: drivingParkedDriving)
        #expect(stops.count == 1)
        let stop = try #require(stops.first)
        #expect(stop.duration >= 28 * 60)
        #expect(abs(stop.metersBefore - 2000) < 20)
    }

    @Test func stopsAtTheVeryStartOrEndAreNotSplitPoints() {
        // Parked 10 minutes, then drive: nothing before the stop to split off.
        var samples = stride(from: 0.0, through: 10, by: 2).map { sample($0, east: 0) }
        samples += (11...15).map { sample(Double($0), east: Double($0 - 10) * 300) }
        #expect(TripEditor.stops(in: samples).isEmpty)
    }

    @Test func nearbyStopsMerge() {
        // Parked, a 2-minute move to another spot, parked again: one stop.
        var samples = (0...5).map { sample(Double($0), east: Double($0) * 300) }
        samples += stride(from: 6.0, through: 14, by: 2).map { sample($0, east: 1500) }
        samples += [sample(15, east: 1800), sample(16, east: 2100)]
        samples += stride(from: 17.0, through: 25, by: 2).map { sample($0, east: 2100) }
        samples += (26...30).map { sample(Double($0), east: 2100 + Double($0 - 25) * 300) }
        #expect(TripEditor.stops(in: samples).count == 1)
    }

    @Test func splitMovesPointsShiftsAndPurpose() throws {
        let container = try ModelContainer(
            for: Trip.self, TripPoint.self, Shift.self, Payout.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let samples = drivingParkedDriving
        let trip = Trip(startedAt: samples[0].timestamp, trigger: .manual)
        trip.endedAt = samples.last?.timestamp
        trip.purpose = .business
        context.insert(trip)
        for s in samples {
            let point = TripPoint(timestamp: s.timestamp, latitude: s.latitude, longitude: s.longitude, speed: 10, horizontalAccuracy: 5)
            context.insert(point)
            point.trip = trip
        }
        // A shift covering only the second drive.
        let shift = Shift(startedAt: t0.addingTimeInterval(39 * 60))
        shift.endedAt = t0.addingTimeInterval(60 * 60)
        context.insert(shift)

        let stops = TripEditor.stops(in: samples)
        let trips = TripEditor.split(trip, at: stops, shifts: [shift], in: context)

        #expect(trips.count == 2)
        #expect(trips[0] === trip)
        #expect(abs(trips[0].distanceMeters - 2000) < 20)
        #expect(abs(trips[1].distanceMeters - 2000) < 20)
        #expect(trips[0].shift == nil)
        #expect(trips[0].purpose == nil)
        #expect(trips[1].shift === shift)
        #expect(trips[1].purpose == .business)
        #expect(trips[0].endedAt! <= trips[1].startedAt)
        // Parked drift points are gone; the two drives keep theirs.
        #expect(trips[0].points.count + trips[1].points.count == 22)
    }
}
