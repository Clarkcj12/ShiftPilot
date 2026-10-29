import Foundation
import SwiftData

/// A car the driver uses for gig work. Everything here stays on the device.
@Model
final class Vehicle {
    var nickname: String = ""
    var vin: String = ""
    var year: Int?
    var make: String = ""
    var model: String = ""
    var trim: String = ""

    var plate: String = ""
    /// State or province on the plate.
    var plateRegion: String = ""
    var registrationExpires: Date?

    var insurer: String = ""
    var policyNumber: String = ""
    var insuranceExpires: Date?

    // Running costs; see `VehicleProfile`.
    var unitsRawValue: String
    var fuelEconomy: Decimal?
    var fuelPrice: Decimal?
    var wearPerDistance: Decimal?

    /// The vehicle new trips are logged against.
    var isCurrent: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \OdometerReading.vehicle)
    var odometerReadings: [OdometerReading] = []

    @Relationship(deleteRule: .nullify, inverse: \Trip.vehicle)
    var trips: [Trip] = []

    @Relationship(deleteRule: .cascade, inverse: \FillUp.vehicle)
    var fillUps: [FillUp] = []

    init(units: VehicleProfile.Units) {
        unitsRawValue = units.rawValue
    }

    var displayName: String {
        if !nickname.isEmpty { return nickname }
        let description = [year.map(String.init), make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return description.isEmpty ? "My vehicle" : description
    }

    /// Year, make, model and trim, e.g. "2021 Toyota Camry SE".
    var details: String {
        [year.map(String.init), make, model, trim].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var profile: VehicleProfile {
        get {
            VehicleProfile(
                units: VehicleProfile.Units(rawValue: unitsRawValue) ?? .us,
                fuelEconomy: fuelEconomy,
                fuelPrice: fuelPrice,
                wearPerDistance: wearPerDistance
            )
        }
        set {
            unitsRawValue = newValue.units.rawValue
            fuelEconomy = newValue.fuelEconomy
            fuelPrice = newValue.fuelPrice
            wearPerDistance = newValue.wearPerDistance
        }
    }

    /// Running costs actually used: measured economy and the latest fill-up price when
    /// there are enough fill-ups, otherwise what the driver entered.
    var effectiveProfile: VehicleProfile {
        var profile = profile
        let snapshots = fillUps.map(\.snapshot)
        if let measured = measuredEconomy {
            profile.fuelEconomy = measured.value
        }
        if let latest = FuelEconomyCalculator.latestPrice(snapshots) {
            profile.fuelPrice = latest.price
        }
        return profile
    }

    var measuredEconomy: MeasuredEconomy? {
        FuelEconomyCalculator.measured(fillUps.map(\.snapshot), units: profile.units)
    }

    var sortedFillUps: [FillUp] {
        fillUps.sorted { $0.date > $1.date }
    }

    /// The highest odometer value on record, from readings or fill-ups.
    var latestOdometer: Decimal? {
        (odometerReadings.map(\.value) + fillUps.map(\.odometer)).max()
    }

    var sortedReadings: [OdometerReading] {
        odometerReadings.sorted { $0.date < $1.date }
    }

    /// Distance driven in `year` (in the vehicle's units) from odometer readings and
    /// fill-ups, if at least two fall in that year.
    func odometerDistance(in year: Int, calendar: Calendar = .current) -> Decimal? {
        let values = (odometerReadings.map { ($0.date, $0.value) } + fillUps.map { ($0.date, $0.odometer) })
            .filter { calendar.component(.year, from: $0.0) == year }
            .map(\.1)
        guard values.count > 1, let low = values.min(), let high = values.max() else { return nil }
        return high - low
    }
}

/// The odometer reading on a date, in the vehicle's distance unit. The IRS expects these
/// (at least at the start and end of the year) to back up a mileage log.
@Model
final class OdometerReading {
    var date: Date
    var value: Decimal
    var vehicle: Vehicle?

    init(date: Date, value: Decimal) {
        self.date = date
        self.value = value
    }
}
