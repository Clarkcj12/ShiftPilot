import Foundation
import SwiftData

/// Whether a trip counts as business mileage.
enum TripPurpose: String, CaseIterable, Identifiable, Codable, Sendable {
    case business, personal

    var id: Self { self }

    var name: String {
        switch self {
        case .business: "Business"
        case .personal: "Personal"
        }
    }
}

@Model
final class Trip {
    var startedAt: Date
    var endedAt: Date?
    var distanceMeters: Double
    var triggerRawValue: String
    var shift: Shift?
    /// nil until classified. Trips logged on a shift start as business; others wait for the driver.
    var purposeRawValue: String? = nil
    /// Fuel + wear per meter when the trip was recorded, so later price changes don't
    /// rewrite past shifts. nil if no vehicle was set up yet.
    var vehicleCostPerMeter: Decimal? = nil

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

    /// Fuel and wear for this trip, using `fallback` when no cost was captured.
    func vehicleCost(fallback: Decimal?) -> Decimal? {
        (vehicleCostPerMeter ?? fallback).map { $0 * Decimal(distanceMeters) }
    }

    var purpose: TripPurpose? {
        get { purposeRawValue.flatMap(TripPurpose.init(rawValue:)) }
        set { purposeRawValue = newValue?.rawValue }
    }
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
