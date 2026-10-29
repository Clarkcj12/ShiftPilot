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

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        migrateLegacyProfile(defaults: defaults)
        current = fetchCurrent()
    }

    /// Fuel + wear per meter for the current vehicle, or nil until it's set up.
    var costPerMeter: Decimal? { current?.effectiveProfile.costPerMeter }

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
            if let next = try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)])).first {
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

    private func fetchCurrent() -> Vehicle? {
        let vehicles = (try? context.fetch(FetchDescriptor<Vehicle>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return vehicles.first(where: \.isCurrent) ?? vehicles.first
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
