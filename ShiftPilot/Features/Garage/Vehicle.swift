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

    var sortedReadings: [OdometerReading] {
        odometerReadings.sorted { $0.date < $1.date }
    }

    /// Distance driven in `year` from odometer readings (in the vehicle's units), if at
    /// least two readings fall in that year.
    func odometerDistance(in year: Int, calendar: Calendar = .current) -> Decimal? {
        let inYear = sortedReadings.filter { calendar.component(.year, from: $0.date) == year }
        guard let first = inYear.first, let last = inYear.last, inYear.count > 1 else { return nil }
        return max(0, last.value - first.value)
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
