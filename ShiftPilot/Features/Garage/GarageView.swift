import SwiftData
import SwiftUI

struct GarageView: View {
    @Environment(GarageStore.self) private var garage
    @Query(sort: \Vehicle.createdAt) private var vehicles: [Vehicle]
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var newVehicle: Vehicle?

    var body: some View {
        List {
            if vehicles.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No vehicles yet", systemImage: "car.side")
                    } description: {
                        Text("Add your car to track running costs, odometer readings and insurance.")
                    } actions: {
                        Button("Add vehicle", action: add)
                            .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    ForEach(vehicles.filter { !$0.isRetired }) { vehicle in
                        NavigationLink {
                            VehicleDetailView(vehicle: vehicle)
                        } label: {
                            VehicleRow(vehicle: vehicle, isCurrent: vehicle == garage.current)
                        }
                    }
                } footer: {
                    Text("New trips are logged against the vehicle marked Current. Vehicle details stay on this iPhone.")
                }

                let retired = vehicles.filter(\.isRetired)
                if !retired.isEmpty {
                    Section("Retired") {
                        ForEach(retired) { vehicle in
                            NavigationLink {
                                VehicleDetailView(vehicle: vehicle)
                            } label: {
                                VehicleRow(vehicle: vehicle, isCurrent: false)
                            }
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    ExpenseListView()
                } label: {
                    Label("Expenses", systemImage: "receipt")
                }
            } footer: {
                Text("Tolls, parking, maintenance, insurance and other costs.")
            }
        }
        .navigationTitle("Garage")
        .toolbar {
            if !vehicles.isEmpty {
                Button("Add vehicle", systemImage: "plus", action: add)
            }
        }
        .navigationDestination(item: $newVehicle) { vehicle in
            VehicleDetailView(vehicle: vehicle)
        }
    }

    private func add() {
        newVehicle = garage.addVehicle(units: VehicleProfile.Units(unit))
    }
}

private struct VehicleRow: View {
    let vehicle: Vehicle
    let isCurrent: Bool

    @Environment(GarageStore.self) private var garage

    var body: some View {
        let profile = garage.effectiveProfile(for: vehicle)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vehicle.displayName).font(.headline)
                if isCurrent {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(.green)
                        .background(.green.opacity(0.15), in: .capsule)
                }
                Spacer()
                Text(profile.isConfigured ? Format.rate(profile.costPerDistance, per: profile.units.distance) : ((profile.fuelEconomy ?? 0) > 0 ? "No fuel price" : "No costs"))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !vehicle.details.isEmpty, vehicle.details != vehicle.displayName {
                Text(vehicle.details).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(VehicleReminder.upcoming(for: vehicle), id: \.title) { reminder in
                Label(reminder.title, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(reminder.isOverdue ? .red : .orange)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Insurance or registration expiring within 30 days, or already expired.
struct VehicleReminder {
    var title: String
    var isOverdue: Bool

    static func upcoming(for vehicle: Vehicle, now: Date = .now, calendar: Calendar = .current) -> [VehicleReminder] {
        [("Insurance", vehicle.insuranceExpires), ("Registration", vehicle.registrationExpires)].compactMap { name, date in
            guard let date else { return nil }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            switch days {
            case ..<0: return VehicleReminder(title: "\(name) expired", isOverdue: true)
            case 0: return VehicleReminder(title: "\(name) expires today", isOverdue: true)
            case 1...30: return VehicleReminder(title: "\(name) expires in \(days) days", isOverdue: false)
            default: return nil
            }
        }
    }
}
