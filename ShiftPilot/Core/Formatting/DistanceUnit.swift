import Foundation

/// Display unit for distances. Trips are stored in meters, so this only affects presentation.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles, kilometers

    static let storageKey = "distanceUnit"

    /// Miles in the US and UK, kilometers elsewhere.
    static var localeDefault: DistanceUnit {
        switch Locale.current.measurementSystem {
        case .us, .uk: .miles
        default: .kilometers
        }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .miles: "Miles"
        case .kilometers: "Kilometers"
        }
    }

    var abbreviation: String {
        switch self {
        case .miles: "mi"
        case .kilometers: "km"
        }
    }

    func value(fromMeters meters: Double) -> Double {
        switch self {
        case .miles: meters / 1609.344
        case .kilometers: meters / 1000
        }
    }

    /// e.g. "12.3 mi". Pass `precise` for two decimals where distance × the mileage rate
    /// should match a deduction shown next to it.
    func format(meters: Double, precise: Bool = false) -> String {
        "\(value(fromMeters: meters).formatted(.number.precision(.fractionLength(precise ? 2 : 1)))) \(abbreviation)"
    }
}
