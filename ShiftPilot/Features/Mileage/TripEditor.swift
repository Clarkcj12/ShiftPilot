import CoreLocation
import SwiftData

/// Classifying, splitting and deleting finished trips.
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

    // MARK: Splitting

    struct Sample: Sendable {
        var timestamp: Date
        var latitude: Double
        var longitude: Double

        var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    /// A stretch where the car stayed parked, as indices into the time-sorted points.
    struct Stop: Identifiable, Equatable, Sendable {
        var startIndex: Int
        var endIndex: Int
        var start: Date
        var end: Date
        /// Distance driven before the stop began.
        var metersBefore: Double

        var id: Int { startIndex }
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// Points within this radius of where the car stopped count as parked (GPS drifts while still).
    static let stopRadius: CLLocationDistance = 150
    static let minimumStop: TimeInterval = 5 * 60
    /// Stops this long are selected for splitting by default.
    static let suggestedStop: TimeInterval = 15 * 60

    /// Parked stretches of at least `minimumStop` inside the trip. Stops touching the first
    /// or last point aren't returned: splitting there would leave an empty trip. Stops
    /// separated by under `minimumStop` of driving are merged, so a quick move between
    /// parking spots doesn't make a tiny trip.
    static func stops(in samples: [Sample]) -> [Stop] {
        guard samples.count > 2 else { return [] }
        var cumulative = [0.0]
        for index in 1..<samples.count {
            cumulative.append(cumulative[index - 1] + samples[index].location.distance(from: samples[index - 1].location))
        }

        var found: [Stop] = []
        var index = 0
        while index < samples.count {
            let anchor = samples[index].location
            var end = index
            while end + 1 < samples.count, samples[end + 1].location.distance(from: anchor) < stopRadius {
                end += 1
            }
            if samples[end].timestamp.timeIntervalSince(samples[index].timestamp) >= minimumStop {
                let stop = Stop(startIndex: index, endIndex: end, start: samples[index].timestamp, end: samples[end].timestamp, metersBefore: cumulative[index])
                if let last = found.last, stop.start.timeIntervalSince(last.end) < minimumStop {
                    found[found.count - 1].endIndex = stop.endIndex
                    found[found.count - 1].end = stop.end
                } else {
                    found.append(stop)
                }
                index = end + 1
            } else {
                index += 1
            }
        }
        return found.filter { $0.startIndex > 0 && $0.endIndex < samples.count - 1 }
    }

    /// The point ranges left after cutting out `stops`: driving before the first stop,
    /// between stops, and after the last. Points inside a stop (parked jitter) are dropped.
    static func pieces(count: Int, cuttingAt stops: [Stop]) -> [ClosedRange<Int>] {
        var pieces: [ClosedRange<Int>] = []
        var start = 0
        for stop in stops.sorted(by: { $0.startIndex < $1.startIndex }) {
            pieces.append(start...stop.startIndex)
            start = stop.endIndex
        }
        pieces.append(start...(count - 1))
        return pieces.filter { $0.count > 1 }
    }

    static func distance(of samples: ArraySlice<Sample>) -> CLLocationDistance {
        zip(samples, samples.dropFirst()).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
    }

    /// Splits a finished trip at `stops`. The original keeps the first piece; each piece
    /// joins the shift it overlaps most and is marked business, or waits for review if it
    /// overlaps none. Returns the trips, in order.
    @discardableResult
    static func split(_ trip: Trip, at stops: [Stop], shifts: [Shift], in context: ModelContext) -> [Trip] {
        guard !trip.isActive, !stops.isEmpty else { return [trip] }
        let points = trip.points.sorted { $0.timestamp < $1.timestamp }
        let samples = points.map { Sample(timestamp: $0.timestamp, latitude: $0.latitude, longitude: $0.longitude) }
        let ranges = pieces(count: points.count, cuttingAt: stops)
        guard ranges.count > 1 else { return [trip] }

        let kept = Set(ranges.flatMap { Array($0) })
        for (index, point) in points.enumerated() where !kept.contains(index) {
            context.delete(point)
        }

        var result: [Trip] = []
        for (number, range) in ranges.enumerated() {
            let piece = number == 0 ? trip : Trip(startedAt: points[range.lowerBound].timestamp, trigger: trip.trigger ?? .manual)
            if number > 0 {
                context.insert(piece)
                piece.vehicle = trip.vehicle
                piece.vehicleCostPerMeter = trip.vehicleCostPerMeter
                for index in range { points[index].trip = piece }
            }
            piece.startedAt = points[range.lowerBound].timestamp
            piece.endedAt = points[range.upperBound].timestamp
            piece.distanceMeters = distance(of: samples[range])
            let shift = shiftOverlappingMost(piece.startedAt...(piece.endedAt ?? piece.startedAt), in: shifts)
            piece.shift = shift
            piece.purpose = shift == nil ? nil : .business
            result.append(piece)
        }
        save(context)
        return result
    }

    static func shiftOverlappingMost(_ interval: ClosedRange<Date>, in shifts: [Shift]) -> Shift? {
        shifts
            .map { shift -> (Shift, TimeInterval) in
                let end = shift.endedAt ?? .now
                let overlap = min(end, interval.upperBound).timeIntervalSince(max(shift.startedAt, interval.lowerBound))
                return (shift, overlap)
            }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
    }
}
