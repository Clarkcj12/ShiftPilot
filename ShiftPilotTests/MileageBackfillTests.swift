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
}
