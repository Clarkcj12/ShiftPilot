import Foundation
import Observation

/// The driver's car, for estimating what each mile actually costs.
///
/// Values are stored in the units they were entered in (US: MPG, price per gallon, wear
/// per mile; elsewhere: L/100 km, price per liter, wear per km), so switching the
/// distance display unit never silently reinterprets them.
struct VehicleProfile: Codable, Equatable, Sendable {
    enum Units: String, Codable, CaseIterable, Identifiable, Sendable {
        case us, metric

        var id: Self { self }

        init(_ distance: DistanceUnit) {
            self = distance == .miles ? .us : .metric
        }

        var title: String {
            switch self {
            case .us: "MPG, per gallon"
            case .metric: "L/100 km, per liter"
            }
        }

        var economyLabel: String { self == .us ? "MPG" : "L/100 km" }
        var volume: String { self == .us ? "gallon" : "liter" }
        var distance: String { self == .us ? "mi" : "km" }
        var metersPerDistance: Double { self == .us ? 1609.344 : 1000 }
    }

    var units: Units
    /// Miles per gallon (`.us`) or liters per 100 km (`.metric`).
    var fuelEconomy: Decimal?
    /// Per gallon or per liter.
    var fuelPrice: Decimal?
    /// Tires, maintenance and depreciation, per mile or per km.
    var wearPerDistance: Decimal?

    var isConfigured: Bool {
        (fuelEconomy ?? 0) > 0 && (fuelPrice ?? 0) > 0
    }

    /// Fuel cost per meter driven.
    var fuelCostPerMeter: Decimal? {
        guard isConfigured, let economy = fuelEconomy, let price = fuelPrice else { return nil }
        switch units {
        case .us: return price / (economy * Decimal(units.metersPerDistance))
        case .metric: return price * economy / 100_000
        }
    }

    var wearCostPerMeter: Decimal {
        (wearPerDistance ?? 0) / Decimal(units.metersPerDistance)
    }

    /// Fuel plus wear per meter, or nil until fuel economy and price are entered.
    var costPerMeter: Decimal? {
        fuelCostPerMeter.map { $0 + wearCostPerMeter }
    }

    /// Cost per mile or km in the profile's own units, for display.
    var costPerDistance: Decimal? {
        costPerMeter.map { $0 * Decimal(units.metersPerDistance) }
    }
}

/// Persists the vehicle profile in UserDefaults.
@MainActor
@Observable
final class VehicleStore {
    private static let key = "vehicleProfile"

    var profile: VehicleProfile {
        didSet { save() }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(VehicleProfile.self, from: data) {
            profile = saved
        } else {
            let unit = defaults.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .localeDefault
            profile = VehicleProfile(units: VehicleProfile.Units(unit))
        }
    }

    var costPerMeter: Decimal? { profile.costPerMeter }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
