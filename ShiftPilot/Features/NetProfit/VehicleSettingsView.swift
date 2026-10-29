import SwiftUI

struct VehicleSettingsView: View {
    @Environment(VehicleStore.self) private var vehicle
    @FocusState private var isEditing: Bool

    var body: some View {
        @Bindable var vehicle = vehicle
        let profile = vehicle.profile
        let units = profile.units

        Form {
            Section {
                Picker("Units", selection: $vehicle.profile.units) {
                    ForEach(VehicleProfile.Units.allCases) { Text($0.title).tag($0) }
                }
                LabeledContent(units.economyLabel) {
                    DecimalField(units == .us ? "e.g. 28" : "e.g. 8.5", value: $vehicle.profile.fuelEconomy)
                }
                LabeledContent("Price per \(units.volume)") {
                    DecimalField("0.00", value: $vehicle.profile.fuelPrice, isCurrency: true)
                }
            } header: {
                Text("Fuel")
            } footer: {
                Text("Use your real-world \(units.economyLabel), from your car's trip computer or a few fill-ups. Update the price when it changes; trips already logged keep the price from when they were driven.")
            }

            Section {
                LabeledContent("Per \(units.distance)") {
                    DecimalField("0.00", value: $vehicle.profile.wearPerDistance, isCurrency: true)
                }
            } header: {
                Text("Wear & tear (optional)")
            } footer: {
                Text("What each \(units.distance == "mi" ? "mile" : "kilometer") costs in tires, oil, maintenance and lost value. Add your yearly maintenance and depreciation, then divide by the distance you drive in a year.")
            }

            Section {
                LabeledContent("Cost per \(units.distance)", value: Format.rate(profile.costPerDistance, per: units.distance))
            } footer: {
                Text(profile.isConfigured
                    ? "Subtracted from your earnings to show net profit. This is your real cost; your tax deduction still uses the IRS mileage rate."
                    : "Enter fuel economy and price to see net profit.")
            }
        }
        .focused($isEditing)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
        .navigationTitle("Vehicle")
    }
}

/// A decimal-pad field that updates its value on every keystroke (a formatted
/// `TextField` only commits when editing ends, which the number pad can't trigger).
private struct DecimalField: View {
    let placeholder: String
    @Binding var value: Decimal?
    var isCurrency = false

    @State private var text = ""

    init(_ placeholder: String, value: Binding<Decimal?>, isCurrency: Bool = false) {
        self.placeholder = placeholder
        _value = value
        self.isCurrency = isCurrency
    }

    var body: some View {
        HStack(spacing: 1) {
            Spacer(minLength: 0)
            if isCurrency {
                Text(Locale.current.currencySymbol ?? "$")
                    .foregroundStyle(text.isEmpty ? .tertiary : .primary)
            }
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .fixedSize()
        }
        .onAppear {
            text = value.map { $0.formatted(.number.grouping(.never)) } ?? ""
        }
        .onChange(of: text) { _, newText in
            value = newText.isEmpty ? nil : Decimal(string: newText, locale: .current)
        }
    }
}
