import Foundation
import Testing
@testable import ShiftPilot

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private let automotive = MotionReading(isAutomotive: true, confidence: .high)
private let stationary = MotionReading(isAutomotive: false, confidence: .high)

struct DriveDetectorTests {
    let config = DetectionConfig()

    private func reduce(_ state: inout DetectorState, _ signal: DriveSignal, at seconds: TimeInterval) -> [DetectorEffect] {
        DriveDetector.reduce(&state, signal, at: t0.addingTimeInterval(seconds), config: config)
    }

    @Test func carConnectStartsConfirmedTripImmediately() {
        var state = DetectorState()
        let effects = reduce(&state, .carConnected(.carPlay), at: 0)
        #expect(state.phase == .driving)
        #expect(effects == [.beginTrip(.carPlay), .confirmTrip])
    }

    @Test func motionOnlyConfirmsAfterSustainedSpeed() {
        var state = DetectorState()
        #expect(reduce(&state, .motion(automotive), at: 0) == [.beginTrip(.motion)])
        #expect(state.phase == .candidate)

        #expect(reduce(&state, .speed(metersPerSecond: 10), at: 5).isEmpty)
        #expect(reduce(&state, .speed(metersPerSecond: 10), at: 40).isEmpty)
        #expect(state.phase == .candidate)

        #expect(reduce(&state, .speed(metersPerSecond: 10), at: 66) == [.confirmTrip])
        #expect(state.phase == .driving)
    }

    @Test func slowingDownResetsTheSpeedHold() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 10), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 2), at: 30)
        #expect(reduce(&state, .speed(metersPerSecond: 10), at: 61).isEmpty)
        #expect(state.phase == .candidate)
    }

    @Test func candidateThatNeverReachesDrivingSpeedIsDiscarded() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 3), at: 10)
        #expect(reduce(&state, .tick, at: 299).isEmpty)
        #expect(reduce(&state, .tick, at: 301) == [.discardTrip])
        #expect(state.phase == .idle)
    }

    @Test func lowConfidenceMotionIsIgnored() {
        var state = DetectorState()
        let effects = reduce(&state, .motion(MotionReading(isAutomotive: true, confidence: .low)), at: 0)
        #expect(effects.isEmpty)
        #expect(state.phase == .idle)
    }

    @Test func carConnectDuringCandidateConfirmsWithoutRestarting() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        #expect(reduce(&state, .carConnected(.carPlay), at: 20) == [.confirmTrip])
        #expect(state.phase == .driving)
    }

    @Test func disconnectThenParkedFinishesTrip() {
        var state = DetectorState()
        _ = reduce(&state, .carConnected(.carPlay), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 590)
        _ = reduce(&state, .carDisconnected(.carPlay), at: 600)
        #expect(state.phase == .ending)
        #expect(reduce(&state, .tick, at: 700).isEmpty)
        #expect(reduce(&state, .tick, at: 771) == [.finishTrip])
        #expect(state.phase == .idle)
    }

    @Test func briefDisconnectDoesNotSplitTheTrip() {
        var state = DetectorState()
        _ = reduce(&state, .carConnected(.carPlay), at: 0)
        _ = reduce(&state, .carDisconnected(.carPlay), at: 600)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 600)
        #expect(reduce(&state, .carConnected(.carPlay), at: 700).isEmpty)
        #expect(state.phase == .driving)
        #expect(reduce(&state, .tick, at: 900).isEmpty)
        #expect(state.phase == .driving)
    }

    @Test func movingAfterDisconnectKeepsTripOpen() {
        var state = DetectorState()
        _ = reduce(&state, .carConnected(.carPlay), at: 0)
        _ = reduce(&state, .carDisconnected(.carPlay), at: 600)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 600)
        _ = reduce(&state, .speed(metersPerSecond: 15), at: 650)
        #expect(reduce(&state, .tick, at: 900).isEmpty)
        #expect(state.phase == .ending)
    }

    @Test func motionOnlyTripEndsWhenMotionStopsAndCarParks() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 10), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 10), at: 60)
        #expect(state.phase == .driving)

        _ = reduce(&state, .speed(metersPerSecond: 0), at: 1000)
        _ = reduce(&state, .motion(stationary), at: 1060)
        #expect(state.phase == .ending)
        #expect(reduce(&state, .tick, at: 1181) == [.finishTrip])
    }

    // MARK: False "possible drive" while not moving

    @Test func stationaryAutomotiveReadingDoesNotStartCandidate() {
        var state = DetectorState()
        let parkedInCar = MotionReading(isAutomotive: true, confidence: .high, isStationary: true)
        #expect(reduce(&state, .motion(parkedInCar), at: 0).isEmpty)
        #expect(state.phase == .idle)
    }

    @Test func candidateDiscardedQuicklyWhenGPSShowsParked() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 5)
        #expect(reduce(&state, .tick, at: 60).isEmpty)
        #expect(reduce(&state, .tick, at: 66) == [.discardTrip])
        #expect(state.phase == .idle)
    }

    @Test func stuckAutomotiveReadingCannotRestartCandidateAfterDiscard() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 0)
        _ = reduce(&state, .tick, at: 61)
        #expect(state.phase == .idle)

        #expect(reduce(&state, .motion(automotive), at: 70).isEmpty)
        #expect(state.phase == .idle)

        _ = reduce(&state, .motion(stationary), at: 200)
        #expect(reduce(&state, .motion(automotive), at: 300) == [.beginTrip(.motion)])
    }

    @Test func carConnectStillStartsTripAfterMotionDiscard() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 0)
        _ = reduce(&state, .tick, at: 61)
        #expect(reduce(&state, .carConnected(.carPlay), at: 70) == [.beginTrip(.carPlay), .confirmTrip])
    }

    // MARK: Manual start/stop

    @Test func manualStartBeginsConfirmedTrip() {
        var state = DetectorState()
        #expect(reduce(&state, .manualStart, at: 0) == [.beginTrip(.manual), .confirmTrip])
        #expect(state.phase == .driving)
    }

    @Test func manualStartDuringCandidateConfirmsIt() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        #expect(reduce(&state, .manualStart, at: 10) == [.confirmTrip])
        #expect(state.phase == .driving)
    }

    @Test func manualTripIgnoresAutoEnd() {
        var state = DetectorState()
        _ = reduce(&state, .manualStart, at: 0)
        _ = reduce(&state, .motion(stationary), at: 10)
        _ = reduce(&state, .speed(metersPerSecond: 0), at: 10)
        #expect(reduce(&state, .tick, at: 3600).isEmpty)
        #expect(state.phase == .driving)

        #expect(reduce(&state, .manualStop, at: 3601) == [.finishTrip])
        #expect(state.phase == .idle)
    }

    @Test func manualStopDuringCandidateDiscards() {
        var state = DetectorState()
        _ = reduce(&state, .motion(automotive), at: 0)
        #expect(reduce(&state, .manualStop, at: 10) == [.discardTrip])
        #expect(state.phase == .idle)
    }

    @Test func manualStopWhileConnectedHoldsOffAutoStartUntilDisconnect() {
        var state = DetectorState()
        _ = reduce(&state, .carConnected(.carPlay), at: 0)
        #expect(reduce(&state, .manualStop, at: 600) == [.finishTrip])

        // Still connected: further signals don't restart a trip.
        #expect(reduce(&state, .motion(automotive), at: 610).isEmpty)
        #expect(reduce(&state, .carConnected(.carPlay), at: 620).isEmpty)
        #expect(state.phase == .idle)

        // Once everything clears, the next connection starts a trip again.
        _ = reduce(&state, .carDisconnected(.carPlay), at: 700)
        _ = reduce(&state, .motion(stationary), at: 700)
        #expect(!state.suppressAutoStart)
        #expect(reduce(&state, .carConnected(.carPlay), at: 900) == [.beginTrip(.carPlay), .confirmTrip])
    }

    @Test func manualStartOverridesSuppression() {
        var state = DetectorState()
        _ = reduce(&state, .carConnected(.carPlay), at: 0)
        _ = reduce(&state, .manualStop, at: 600)
        #expect(reduce(&state, .manualStart, at: 610) == [.beginTrip(.manual), .confirmTrip])
        #expect(state.phase == .driving)
    }
}

@MainActor
struct AutoDriveDetectionManagerTests {
    @Test func forwardsEffectsToTrackerAndFeedsSpeedBack() {
        let tracker = MockTracker()
        let clock = TestClock()
        let manager = AutoDriveDetectionManager(sources: [], tracker: tracker, now: { clock.now })

        manager.handle(.carConnected(.bluetoothAudio(uid: "car", name: "My Car")))
        #expect(tracker.calls == [.begin(.bluetoothAudio), .confirm])

        tracker.onSpeed?(0)
        manager.handle(.carDisconnected(.bluetoothAudio(uid: "car", name: "My Car")))
        clock.now = t0.addingTimeInterval(200)
        manager.handle(.tick)

        #expect(tracker.calls == [.begin(.bluetoothAudio), .confirm, .finish])
        #expect(manager.state.phase == .idle)
    }
}

@MainActor
private final class TestClock {
    var now = t0
}

@MainActor
private final class MockTracker: TripTracking {
    enum Call: Equatable {
        case begin(TripTrigger), confirm, finish, discard
    }

    var onSpeed: (@MainActor (Double) -> Void)?
    private(set) var calls: [Call] = []

    func beginTrip(trigger: TripTrigger) { calls.append(.begin(trigger)) }
    func confirmTrip() { calls.append(.confirm) }
    func finishTrip() { calls.append(.finish) }
    func discardTrip() { calls.append(.discard) }
}

struct DistanceUnitTests {
    @Test func convertsAndFormatsMeters() {
        #expect(abs(DistanceUnit.miles.value(fromMeters: 1609.344) - 1) < 1e-9)
        #expect(DistanceUnit.kilometers.value(fromMeters: 2500) == 2.5)
        #expect(DistanceUnit.kilometers.format(meters: 12_345) == "12.3 km")
        #expect(DistanceUnit.miles.format(meters: 16_093.44) == "10.0 mi")
    }
}
