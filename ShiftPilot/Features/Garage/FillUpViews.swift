import SwiftUI

/// Logs a new fill-up or edits one.
struct FillUpEditorView: View {
    let vehicle: Vehicle
    let fillUp: FillUp?

    @Environment(GarageStore.self) private var garage
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var odometer: Decimal?
    @State private var volume: Decimal?
    @State private var totalCost: Decimal?
    @State private var isFullTank: Bool
    @State private var note: String
    @State private var isConfirmingDelete = false
    @State private var deleteOnDisappear = false

    init(vehicle: Vehicle, fillUp: FillUp? = nil) {
        self.vehicle = vehicle
        self.fillUp = fillUp
        _date = State(initialValue: fillUp?.date ?? .now)
        _odometer = State(initialValue: fillUp?.odometer)
        _volume = State(initialValue: fillUp?.volume)
        _totalCost = State(initialValue: fillUp?.totalCost)
        _isFullTank = State(initialValue: fillUp?.isFullTank ?? true)
        _note = State(initialValue: fillUp?.note ?? "")
    }

    var body: some View {
        let units = vehicle.profile.units
        let price = volume.flatMap { volume in totalCost.map { volume > 0 ? $0 / volume : 0 } }
        let lastOdometer = vehicle.fillUps.filter { $0 != fillUp }.map(\.odometer).max()

        NavigationStack {
            Form {
                Section {
                    LabeledContent("Odometer (\(units.distance))") {
                        DecimalField(lastOdometer.map { "last \($0.formatted(.number.precision(.fractionLength(0))))" } ?? "e.g. 48210", value: $odometer)
                    }
                    LabeledContent(units == .us ? "Gallons" : "Liters") {
                        DecimalField("e.g. 11.2", value: $volume)
                    }
                    LabeledContent("Total cost") {
                        DecimalField("0.00", value: $totalCost, isCurrency: true)
                    }
                    LabeledContent("Price per \(units.volume)", value: price.map { Format.fuelPrice($0) } ?? "—")
                } footer: {
                    if let odometer, let lastOdometer, odometer < lastOdometer, fillUp == nil {
                        Text("That's lower than your last fill-up (\(lastOdometer.formatted()) \(units.distance)). Check the number.")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Toggle("Filled the tank", isOn: $isFullTank)
                    DatePicker("Date", selection: $date, in: ...Date.now)
                    TextField("Note (optional)", text: $note)
                } footer: {
                    Text("Fill until the pump clicks off and leave this on. \(units.economyLabel) is measured between full fills; partial top-ups are counted toward the next one.")
                }

                if fillUp != nil {
                    Section {
                        Button("Delete fill-up", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .foregroundStyle(.red)
                        .confirmationDialog("Delete this fill-up?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete fill-up", role: .destructive) {
                                deleteOnDisappear = true
                                dismiss()
                            }
                        }
                    }
                }
            }
            .keyboardDoneButton()
            .navigationTitle(fillUp == nil ? "Log fill-up" : "Edit fill-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!isValid)
                }
            }
            .onDisappear {
                if deleteOnDisappear, let fillUp {
                    garage.deleteFillUp(fillUp)
                }
            }
        }
    }

    private var isValid: Bool {
        (odometer ?? 0) > 0 && (volume ?? 0) > 0 && (totalCost ?? 0) > 0
    }

    private func save() {
        guard let odometer, let volume, let totalCost, isValid else { return }
        if let fillUp {
            fillUp.date = date
            fillUp.odometer = odometer
            fillUp.volume = volume
            fillUp.totalCost = totalCost
            fillUp.isFullTank = isFullTank
            fillUp.note = note
            garage.save()
        } else {
            garage.addFillUp(
                FillUp(date: date, odometer: odometer, volume: volume, totalCost: totalCost, isFullTank: isFullTank, note: note),
                to: vehicle
            )
        }
        dismiss()
    }
}

struct FillUpRow: View {
    let fillUp: FillUp
    let units: VehicleProfile.Units

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(fillUp.date, format: .dateTime.month().day().year())
                Text("\(fillUp.volume.formatted(.number.precision(.fractionLength(0...3)))) \(units == .us ? "gal" : "L") · \(fillUp.odometer.formatted(.number.precision(.fractionLength(0)))) \(units.distance)\(fillUp.isFullTank ? "" : " · partial")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(fillUp.totalCost)).monospacedDigit()
                if let price = fillUp.pricePerUnit {
                    Text("\(Format.fuelPrice(price))/\(units == .us ? "gal" : "L")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FillUpListView: View {
    let vehicle: Vehicle

    @Environment(GarageStore.self) private var garage
    @State private var editing: FillUp?

    var body: some View {
        let units = vehicle.profile.units
        let fillUps = vehicle.sortedFillUps
        List {
            ForEach(fillUps) { fillUp in
                Button {
                    editing = fillUp
                } label: {
                    FillUpRow(fillUp: fillUp, units: units).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            .onDelete { offsets in
                for index in offsets {
                    garage.deleteFillUp(fillUps[index])
                }
            }
        }
        .overlay {
            if fillUps.isEmpty {
                ContentUnavailableView("No fill-ups", systemImage: "fuelpump", description: Text("Log fill-ups to measure your real \(units.economyLabel)."))
            }
        }
        .navigationTitle("Fill-ups")
        .sheet(item: $editing) { fillUp in
            FillUpEditorView(vehicle: vehicle, fillUp: fillUp)
        }
    }
}

/// Measured economy, latest price and recent fill-ups for a vehicle.
struct FillUpsSection: View {
    let vehicle: Vehicle
    @Binding var isLogging: Bool

    @State private var editing: FillUp?

    var body: some View {
        let units = vehicle.profile.units
        let snapshots = vehicle.fillUps.map(\.snapshot)
        let measured = vehicle.measuredEconomy
        let latest = FuelEconomyCalculator.latestPrice(snapshots)

        Section {
            if let measured {
                LabeledContent("Measured \(units.economyLabel)", value: measured.value.formatted(.number.precision(.fractionLength(1))))
            }
            if let latest {
                LabeledContent("Latest price", value: "\(Format.fuelPrice(latest.price))/\(units.volume)")
            }
            ForEach(vehicle.sortedFillUps.prefix(3)) { fillUp in
                Button {
                    editing = fillUp
                } label: {
                    FillUpRow(fillUp: fillUp, units: units).contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            if vehicle.fillUps.count > 3 {
                NavigationLink("All fill-ups (\(vehicle.fillUps.count))") {
                    FillUpListView(vehicle: vehicle)
                }
            }
            Button("Log fill-up", systemImage: "fuelpump") {
                isLogging = true
            }
        } header: {
            Text("Fill-ups")
        } footer: {
            Text(footer(measured: measured, hasPrice: latest != nil, units: units))
        }
        .sheet(item: $editing) { fillUp in
            FillUpEditorView(vehicle: vehicle, fillUp: fillUp)
        }
    }

    private func footer(measured: MeasuredEconomy?, hasPrice: Bool, units: VehicleProfile.Units) -> String {
        if let measured {
            return "Net profit uses your measured \(units.economyLabel) (last \(measured.intervals) full \(measured.intervals == 1 ? "tank" : "tanks")) and latest pump price."
        }
        let fulls = vehicle.fillUps.filter(\.isFullTank).count
        let needed = max(0, 2 - fulls)
        let price = hasPrice ? "Your latest pump price is already used. " : ""
        return price + "Log \(needed == 1 ? "one more full fill-up" : "two full fill-ups") to measure your real \(units.economyLabel); until then the estimate below is used."
    }
}
