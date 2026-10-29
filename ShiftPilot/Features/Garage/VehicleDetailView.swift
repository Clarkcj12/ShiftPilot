import SwiftUI

struct VehicleDetailView: View {
    @Bindable var vehicle: Vehicle

    @Environment(GarageStore.self) private var garage
    @Environment(\.dismiss) private var dismiss
    @State private var isLookingUp = false
    @State private var lookupMessage: String?
    @State private var isAddingReading = false
    @State private var isLoggingFillUp = false
    @State private var isConfirmingDelete = false
    /// Deleted once the view is gone, so it never renders a deleted model.
    @State private var deleteOnDisappear = false

    var body: some View {
        let profile = vehicle.profile
        let effective = garage.effectiveProfile(for: vehicle)
        let priceSource = garage.fuelPriceSource(for: vehicle)
        let units = profile.units

        Form {
            Section {
                TextField("Nickname (optional)", text: $vehicle.nickname)
                HStack {
                    TextField("VIN", text: $vehicle.vin)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                    if isLookingUp {
                        ProgressView()
                    } else {
                        Button("Look up", action: lookUp)
                            .disabled(VINDecoder.normalize(vehicle.vin).count != 17)
                    }
                }
                TextField("Year", text: yearText)
                    .keyboardType(.numberPad)
                TextField("Make", text: $vehicle.make)
                TextField("Model", text: $vehicle.model)
                TextField("Trim (optional)", text: $vehicle.trim)
            } header: {
                Text("Vehicle")
            } footer: {
                Text(lookupMessage ?? "Look up fills in year, make and model from the VIN using NHTSA's free decoder. Only the VIN is sent.")
            }

            Section("Plate & registration") {
                TextField("Plate number", text: $vehicle.plate)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField("State", text: $vehicle.plateRegion)
                    .textInputAutocapitalization(.characters)
                OptionalDateRow(title: "Registration expires", date: $vehicle.registrationExpires)
            }

            Section("Insurance") {
                TextField("Insurance company", text: $vehicle.insurer)
                TextField("Policy number", text: $vehicle.policyNumber)
                    .autocorrectionDisabled()
                OptionalDateRow(title: "Policy expires", date: $vehicle.insuranceExpires)
            }

            FillUpsSection(vehicle: vehicle, isLogging: $isLoggingFillUp)

            Section {
                Picker("Units", selection: $vehicle.profile.units) {
                    ForEach(VehicleProfile.Units.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(vehicle.measuredEconomy == nil ? units.economyLabel : "Estimated \(units.economyLabel)") {
                    DecimalField(units == .us ? "e.g. 28" : "e.g. 8.5", value: $vehicle.profile.fuelEconomy)
                }
                LabeledContent("Price per \(units.volume)") {
                    DecimalField(pricePlaceholder(priceSource), value: $vehicle.profile.fuelPrice, isCurrency: true)
                }
                if let note = priceNote(priceSource, units: units) {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Wear & tear per \(units.distance)") {
                    DecimalField("0.00", value: $vehicle.profile.wearPerDistance, isCurrency: true)
                }
                LabeledContent("Cost per \(units.distance)", value: Format.rate(effective.costPerDistance, per: units.distance))
                    .fontWeight(.semibold)
            } header: {
                Text("Running costs")
            } footer: {
                Text("Use your real-world \(units.economyLabel). Wear & tear covers tires, maintenance and lost value. Trips already logged keep the cost from when they were driven; your tax deduction still uses the IRS rate.")
            }

            OdometerSection(vehicle: vehicle, units: units, isAddingReading: $isAddingReading)

            Section {
                if vehicle.isRetired {
                    Button("Put back in service", systemImage: "arrow.uturn.backward.circle") {
                        garage.reinstate(vehicle)
                    }
                } else {
                    if vehicle != garage.current {
                        Button("Use for new trips", systemImage: "checkmark.circle") {
                            garage.makeCurrent(vehicle)
                        }
                    }
                    Button("Retire vehicle", systemImage: "archivebox") {
                        garage.retire(vehicle)
                        dismiss()
                    }
                }
                Button("Delete vehicle", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .foregroundStyle(.red)
                .confirmationDialog("Delete this vehicle?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete vehicle and its records", role: .destructive) {
                        deleteOnDisappear = true
                        dismiss()
                    }
                } message: {
                    Text(deleteMessage)
                }
            } footer: {
                Text("Sold or replaced this car? Retire it to keep its fill-ups, odometer readings and expenses for your tax records.")
            }
        }
        .keyboardDoneButton()
        .navigationTitle(vehicle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: vehicle.plateRegion) {
            if vehicle == garage.current {
                await garage.refreshFuelPrice()
            }
        }
        .sheet(isPresented: $isLoggingFillUp) {
            FillUpEditorView(vehicle: vehicle)
        }
        .sheet(isPresented: $isAddingReading) {
            AddOdometerReadingView(vehicle: vehicle, units: units)
        }
        .onDisappear {
            if deleteOnDisappear {
                garage.delete(vehicle)
            } else {
                garage.save()
            }
        }
    }

    private var deleteMessage: String {
        var lost: [String] = []
        if !vehicle.fillUps.isEmpty { lost.append("\(vehicle.fillUps.count) fill-up\(vehicle.fillUps.count == 1 ? "" : "s")") }
        if !vehicle.odometerReadings.isEmpty { lost.append("\(vehicle.odometerReadings.count) odometer reading\(vehicle.odometerReadings.count == 1 ? "" : "s")") }
        let removed = lost.isEmpty ? "Its details are removed." : "This permanently deletes \(lost.formatted(.list(type: .and)))."
        return removed + " Trips and expenses stay, without a vehicle. To keep everything, retire it instead."
    }

    private var yearText: Binding<String> {
        Binding {
            vehicle.year.map(String.init) ?? ""
        } set: { text in
            vehicle.year = Int(text.filter(\.isNumber).prefix(4))
        }
    }

    /// Shows the price in use as the placeholder, so an empty field doesn't look like $0.
    private func pricePlaceholder(_ source: FuelPriceSource) -> String {
        switch source {
        case .fillUp(let price, _), .regional(let price, _): Format.fuelPrice(price)
        case .entered, .none: "0.00"
        }
    }

    private func priceNote(_ source: FuelPriceSource, units: VehicleProfile.Units) -> String? {
        switch source {
        case .fillUp(_, let date):
            return "From your fill-up on \(date.formatted(date: .abbreviated, time: .omitted))."
        case .regional(let price, let regional):
            let week = regional.weekOf.formatted(.dateTime.month(.abbreviated).day())
            return "Using the \(regional.areaName) average for regular, \(Format.fuelPrice(price))/\(units.volume), week of \(week) (U.S. EIA). Enter your own price or log a fill-up to replace it."
        case .entered, .none:
            return nil
        }
    }

    private func lookUp() {
        let vin = VINDecoder.normalize(vehicle.vin)
        vehicle.vin = vin
        isLookingUp = true
        lookupMessage = nil
        Task {
            defer { isLookingUp = false }
            do {
                let decoded = try await VINDecoder.decode(vin)
                vehicle.year = decoded.year ?? vehicle.year
                vehicle.make = decoded.make
                vehicle.model = decoded.model
                if !decoded.trim.isEmpty { vehicle.trim = decoded.trim }
                lookupMessage = VINDecoder.hasValidCheckDigit(vin)
                    ? "Found \(vehicle.details)."
                    : "Found \(vehicle.details). The VIN's check digit doesn't match, so double-check it against your registration."
            } catch {
                lookupMessage = error.localizedDescription
            }
        }
    }
}

private struct OdometerSection: View {
    let vehicle: Vehicle
    let units: VehicleProfile.Units
    @Binding var isAddingReading: Bool

    @Environment(GarageStore.self) private var garage

    var body: some View {
        let readings = vehicle.sortedReadings.reversed()
        let year = Calendar.current.component(.year, from: .now)
        Section {
            if let driven = vehicle.odometerDistance(in: year) {
                LabeledContent("Driven in \(String(year))", value: "\(driven.formatted(.number.precision(.fractionLength(0)))) \(units.distance)")
            }
            ForEach(Array(readings)) { reading in
                LabeledContent {
                    Text("\(reading.value.formatted(.number.precision(.fractionLength(0)))) \(units.distance)")
                        .monospacedDigit()
                } label: {
                    Text(reading.date, format: .dateTime.month().day().year())
                }
            }
            .onDelete { offsets in
                let list = Array(readings)
                for index in offsets {
                    garage.deleteReading(list[index])
                }
            }
            Button("Add reading", systemImage: "plus") {
                isAddingReading = true
            }
        } header: {
            Text("Odometer")
        } footer: {
            Text("Record the odometer at least on January 1 and December 31. The IRS asks for your vehicle's total miles for the year, and these readings back up your mileage log.")
        }
    }
}

private struct AddOdometerReadingView: View {
    let vehicle: Vehicle
    let units: VehicleProfile.Units

    @Environment(GarageStore.self) private var garage
    @Environment(\.dismiss) private var dismiss
    @State private var value: Decimal?
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Odometer (\(units.distance))") {
                        DecimalField("e.g. 48210", value: $value)
                    }
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                } footer: {
                    if let last = vehicle.sortedReadings.last, let value, value < last.value, date > last.date {
                        Text("That's lower than your last reading (\(last.value.formatted()) \(units.distance)). Check the number.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Odometer reading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value {
                            garage.addReading(value, on: date, to: vehicle)
                        }
                        dismiss()
                    }
                    .disabled((value ?? 0) <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// A date that may not be set: "Add" until there is one, then a picker with a clear button.
private struct OptionalDateRow: View {
    let title: String
    @Binding var date: Date?

    var body: some View {
        if let current = date {
            HStack {
                DatePicker(title, selection: Binding { current } set: { date = $0 }, displayedComponents: .date)
                Button("Clear", systemImage: "xmark.circle.fill") { date = nil }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        } else {
            LabeledContent(title) {
                Button("Add date") {
                    date = Calendar.current.date(byAdding: .year, value: 1, to: .now)
                }
            }
        }
    }
}
