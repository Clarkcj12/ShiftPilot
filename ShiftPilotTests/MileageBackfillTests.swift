import CoreLocation
import Foundation
import Testing
@testable import ShiftPilot

@MainActor
struct MileageBackfillTests {
    private func fix(_ seconds: TimeInterval, speed: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 38.3 + seconds / 10_000, longitude: -76.5),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: speed,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    @Test func backfillStartsWhereTheCarPulledAway() {
        // Parked, then walking pace (not driving), then pulling away.
        let fixes = [fix(0, speed: 8), fix(10, speed: 0), fix(20, speed: 1.4), fix(30, speed: 4), fix(40, speed: 9)]
        let backfill = MileageTracker.backfill(fixes, startSpeed: 2.5)
        #expect(backfill.map(\.timestamp.timeIntervalSinceReferenceDate) == [20, 30, 40])
    }

    @Test func backfillKeepsEverythingWhenNeverParked() {
        let fixes = [fix(0, speed: 8), fix(10, speed: 9)]
        #expect(MileageTracker.backfill(fixes, startSpeed: 2.5).count == 2)
    }

    @Test func invalidSpeedDoesNotCountAsParked() {
        let fixes = [fix(0, speed: 0), fix(10, speed: -1), fix(20, speed: 9)]
        #expect(MileageTracker.backfill(fixes, startSpeed: 2.5).count == 3)
    }

    @Test func staleParkedFixDoesntBackdateTheTrip() {
        // Last parked fix 7 minutes before the car was next seen (trip 12, Oct 29).
        let backfill = [fix(0, speed: 0), fix(429, speed: 5.7), fix(430, speed: 4)]
        #expect(MileageTracker.tripStart(backfill)?.timeIntervalSinceReferenceDate == 399)
    }

    @Test func recentParkedFixIsTheTripStart() {
        let backfill = [fix(0, speed: 0), fix(10, speed: 5)]
        #expect(MileageTracker.tripStart(backfill)?.timeIntervalSinceReferenceDate == 0)
        #expect(MileageTracker.tripStart([]) == nil)
    }

    /// A fix `east` meters east and `north` meters north of a point, `seconds` in.
    private func at(_ seconds: TimeInterval, east: Double, north: Double = 0, speed: Double) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 38.3 + north / 111_000, longitude: -76.5 + east / 87_000),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, speed: speed,
            timestamp: Date(timeIntervalSinceReferenceDate: seconds)
        )
    }

    @Test func walkingAroundAStoreAddsOnlyTheStraightLine() {
        // Drive 1 km east, walk a 60 m loop through the store and back, drive 1 km on.
        let fixes = [
            at(0, east: 0, speed: 15), at(67, east: 1000, speed: 15),
            at(120, east: 1030, speed: 1.3), at(180, east: 1030, north: 30, speed: 1.3),
            at(240, east: 1000, north: 30, speed: 1.3), at(300, east: 1000, speed: 1.3),
            at(367, east: 2000, speed: 15),
        ]
        let straight = fixes[0].distance(from: fixes[1]) + fixes[1].distance(from: fixes[6])
        let zigzag = zip(fixes, fixes.dropFirst()).reduce(0) { $0 + $1.0.distance(from: $1.1) }
        let distance = MileageTracker.distance(of: fixes)
        #expect(abs(distance - straight) < 1)
        #expect(zigzag - distance > 100)
    }

    @Test func drivingFixesStillAddUp() {
        let fixes = [at(0, east: 0, speed: 15), at(10, east: 150, speed: 15), at(20, east: 300, speed: 15)]
        #expect(abs(MileageTracker.distance(of: fixes) - 300) < 2)
    }

    @Test func slowFixesStillReportSpeed() {
        let step = MileageTracker.step(from: at(0, east: 0, speed: 15), to: at(10, east: 20, speed: 1))
        #expect(step.speed == 1)
        #expect(step.delta == nil)
    }
}
