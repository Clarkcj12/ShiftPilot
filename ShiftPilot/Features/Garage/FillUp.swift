import Foundation
import SwiftData

/// A trip to the pump. Volume is in the vehicle's units (gallons or liters) and the
/// odometer in its distance unit (miles or km).
@Model
final class FillUp {
    var date: Date
    var odometer: Decimal
    var volume: Decimal
    var totalCost: Decimal
    /// Filled until the pump clicked off. Economy is measured between full fills.
    var isFullTank: Bool = true
    var note: String = ""
    var vehicle: Vehicle?

    init(date: Date, odometer: Decimal, volume: Decimal, totalCost: Decimal, isFullTank: Bool = true, note: String = "") {
        self.date = date
        self.odometer = odometer
        self.volume = volume
        self.totalCost = totalCost
        self.isFullTank = isFullTank
        self.note = note
    }

    var pricePerUnit: Decimal? {
        volume > 0 ? totalCost / volume : nil
    }

    var snapshot: FillUpSnapshot {
        FillUpSnapshot(date: date, odometer: odometer, volume: volume, totalCost: totalCost, isFullTank: isFullTank)
    }
}

struct FillUpSnapshot: Sendable, Equatable {
    var date: Date
    var odometer: Decimal
    var volume: Decimal
    var totalCost: Decimal
    var isFullTank: Bool
}

struct MeasuredEconomy: Sendable, Equatable {
    /// MPG (`.us`) or L/100 km (`.metric`).
    var value: Decimal
    /// Full-to-full intervals it's based on.
    var intervals: Int
}

enum FuelEconomyCalculator {
    /// Recent intervals only, so it tracks seasons and driving changes.
    static let maxIntervals = 5

    /// Full-to-full economy: distance between two full fills over all fuel added after
    /// the first (partial top-ups included). Needs at least two full fills.
    static func measured(_ fillUps: [FillUpSnapshot], units: VehicleProfile.Units) -> MeasuredEconomy? {
        let sorted = fillUps.sorted { $0.odometer < $1.odometer }
        var intervals: [(distance: Decimal, fuel: Decimal)] = []
        var lastFull: Decimal?
        var fuelSinceFull: Decimal = 0

        for fill in sorted {
            fuelSinceFull += fill.volume
            guard fill.isFullTank else { continue }
            if let start = lastFull, fill.odometer > start {
                intervals.append((fill.odometer - start, fuelSinceFull))
            }
            lastFull = fill.odometer
            fuelSinceFull = 0
        }

        let recent = intervals.suffix(maxIntervals)
        let distance = recent.reduce(Decimal(0)) { $0 + $1.distance }
        let fuel = recent.reduce(Decimal(0)) { $0 + $1.fuel }
        guard !recent.isEmpty, distance > 0, fuel > 0 else { return nil }

        let value = units == .us ? distance / fuel : fuel * 100 / distance
        return MeasuredEconomy(value: TaxCalculator.round(value), intervals: recent.count)
    }

    /// Price per gallon or liter at the most recent fill-up.
    static func latestPrice(_ fillUps: [FillUpSnapshot]) -> (price: Decimal, date: Date)? {
        guard let latest = fillUps.filter({ $0.volume > 0 }).max(by: { $0.date < $1.date }) else { return nil }
        return (latest.totalCost / latest.volume, latest.date)
    }
}
