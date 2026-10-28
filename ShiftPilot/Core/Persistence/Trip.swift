import Foundation
import SwiftData

@Model
final class Trip {
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var triggerRawValue: String

    @Relationship(deleteRule: .cascade, inverse: \TripPoint.trip)
    var points: [TripPoint] = []

    init(startedAt: Date, trigger: TripTrigger) {
        self.startedAt = startedAt
        self.distanceMeters = 0
        self.triggerRawValue = trigger.rawValue
    }

    var trigger: TripTrigger? { TripTrigger(rawValue: triggerRawValue) }
    var miles: Double { distanceMeters / 1609.344 }
    var isActive: Bool { endedAt == nil }
}

@Model
final class TripPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Meters per second; negative when invalid.
    var speed: Double
    var horizontalAccuracy: Double
    var trip: Trip?

    init(timestamp: Date, latitude: Double, longitude: Double, speed: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }
}
