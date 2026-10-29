import Foundation
import Observation
import SwiftData

/// Owns the driver's vehicles and which one new trips are logged against.
@MainActor
@Observable
final class GarageStore {
    /// Pre-Garage builds kept one vehicle profile here.
    static let legacyProfileKey = "vehicleProfile"

    private(set) var current: Vehicle?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored let fuelPrices: FuelPriceStore

    init(context: ModelContext, defaults: UserDefaults = .standard, fuelPrices: FuelPriceStore? = nil) {
        self.context = context
        self.fuelPrices = fuelPrices ?? FuelPriceStore(defaults: defaults, apiKey: nil)
        migrateLegacyProfile(defaults: defaults)
        current = fetchCurrent()
    }

    /// Fuel + wear per meter for the current vehicle, or nil until it's set up.
    var costPerMeter: Decimal? { current.flatMap { effectiveProfile(for: $0).costPerMeter } }

    /// The regional average for this vehicle's plate state, if one has been fetched.
    func regionalFuelPrice(for vehicle: Vehicle) -> RegionalFuelPrice? {
        fuelPrices.price(forState: vehicle.plateRegion)
    }

    func effectiveProfile(for vehicle: Vehicle) -> VehicleProfile {
        vehicle.effectiveProfile(regional: regionalFuelPrice(for: vehicle))
    }

    func fuelPriceSource(for vehicle: Vehicle) -> FuelPriceSource {
        vehicle.fuelPriceSource(regional: regionalFuelPrice(for: vehicle))
    }

    /// Fetches the regional average for the current vehicle's state (at most daily).
    func refreshFuelPrice() async {
        await fuelPrices.refreshIfNeeded(state: current?.plateRegion)
    }

    @discardableResult
    func addVehicle(units: VehicleProfile.Units) -> Vehicle {
        let vehicle = Vehicle(units: units)
        context.insert(vehicle)
        if current == nil {
            vehicle.isCurrent = true
            current = vehicle
        }
        save()
        return vehicle
    }

    /// Stops using a vehicle but keeps its records.
    func retire(_ vehicle: Vehicle) {
        vehicle.isRetired = true
        vehicle.isCurrent = false
        if vehicle == current {
            current = nil
            if let next = activeVehicles().first(where: { $0 != vehicle }) {
                makeCurrent(next)
            }
        }
        save()
    }

    func reinstate(_ vehicle: Vehicle) {
        vehicle.isRetired = false
        if current == nil {
            makeCurrent(vehicle)
        }
        save()
    }

    func makeCurrent(_ vehicle: Vehicle) {
        for other in (try? context.fetch(FetchDescriptor<Vehicle>())) ?? [] {
            other.isCurrent = other == vehicle
        }
        current = vehicle
        save()
    }

    func delete(_ vehicle: Vehicle) {
        let wasCurrent = vehicle == current
        context.delete(vehicle)
        save()
        if wasCurrent {
            current = nil
            if let next = activeVehicles().first {
                makeCurrent(next)
            }
        }
    }

    func addReading(_ value: Decimal, on date: Date, to vehicle: Vehicle) {
        let reading = OdometerReading(date: date, value: value)
        context.insert(reading)
        reading.vehicle = vehicle
        save()
    }

    func addFillUp(_ fillUp: FillUp, to vehicle: Vehicle) {
        context.insert(fillUp)
        fillUp.vehicle = vehicle
        save()
    }

    func deleteFillUp(_ fillUp: FillUp) {
        context.delete(fillUp)
        save()
    }

    func deleteReading(_ reading: OdometerReading) {
        context.delete(reading)
        save()
    }

    func save() {
        do {
            try context.save()
        } catch {
            Log.persistence.error("Garage save failed: \(error.localizedDescription)")
        }
    }

    private func activeVehicles() -> [Vehicle] {
        ((try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []).filter { !$0.isRetired }
    }

    private func fetchCurrent() -> Vehicle? {
        let vehicles = activeVehicles()
        return vehicles.first(where: \.isCurrent) ?? vehicles.first
    }

    // MARK: Expenses

    func add(_ expense: Expense) {
        context.insert(expense)
        save()
    }

    func delete(_ expense: Expense) {
        context.delete(expense)
        save()
    }

    /// The shift whose time span contains `date`, for linking tolls and parking.
    func shift(containing date: Date) -> Shift? {
        let shifts = (try? context.fetch(FetchDescriptor<Shift>(predicate: #Predicate { $0.startedAt <= date }, sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))) ?? []
        return shifts.first { ($0.endedAt ?? .distantFuture) >= date }
    }

    /// Turns the old single vehicle profile into the first Garage vehicle.
    private func migrateLegacyProfile(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: Self.legacyProfileKey) else { return }
        defer { defaults.removeObject(forKey: Self.legacyProfileKey) }
        guard (try? context.fetchCount(FetchDescriptor<Vehicle>())) == 0,
              let profile = try? JSONDecoder().decode(VehicleProfile.self, from: data) else { return }
        let vehicle = Vehicle(units: profile.units)
        vehicle.profile = profile
        vehicle.isCurrent = true
        context.insert(vehicle)
        save()
        Log.persistence.info("Moved vehicle profile into the Garage")
    }
}
