import SwiftUI

struct AddPayoutView: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastPayoutPlatform") private var platform: GigPlatform = .doorDash
    @State private var amount: Decimal?
    @State private var receivedAt: Date
    @State private var note = ""
    @FocusState private var isAmountFocused: Bool

    private let latestAllowed: Date

    init(shift: Shift) {
        self.shift = shift
        let latest = shift.endedAt ?? .now
        latestAllowed = latest
        _receivedAt = State(initialValue: latest)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Platform") {
                    PlatformPicker(selection: $platform)
                }

                Section {
                    TextField("Amount", value: $amount, format: .currency(code: Format.currencyCode))
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                        .focused($isAmountFocused)
                } header: {
                    Text("Amount")
                } footer: {
                    Text("Total pay for the order or batch, including tips.")
                }

                Section {
                    DatePicker("Received", selection: $receivedAt, in: shift.startedAt...latestAllowed)
                    TextField("Note (optional)", text: $note)
                }
            }
            .navigationTitle("Add payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let amount else { return }
                        shifts.addPayout(amount, platform: platform, receivedAt: receivedAt, note: note, to: shift)
                        dismiss()
                    }
                    .disabled((amount ?? 0) <= 0)
                }
            }
            .onAppear { isAmountFocused = true }
        }
        .presentationDetents([.large])
    }
}
