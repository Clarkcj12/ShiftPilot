import SwiftData
import SwiftUI

/// Adds a payout to a shift, or edits/deletes an existing one.
struct AddPayoutView: View {
    let shift: Shift
    let payout: Payout?

    @Environment(ShiftManager.self) private var shifts
    @Environment(\.dismiss) private var dismiss
    @Query private var allPayouts: [Payout]
    @AppStorage("lastPayoutPlatform") private var lastPlatform: GigPlatform = .doorDash
    @State private var platform: GigPlatform
    @State private var amount: Decimal?
    @State private var tip: Decimal?
    @State private var receivedAt: Date
    @State private var note: String
    @State private var isConfirmingDelete = false
    /// Deleted once the sheet is gone, so it never renders a deleted model.
    @State private var deleteOnDisappear = false
    @FocusState private var isAmountFocused: Bool

    private let latestAllowed: Date

    init(shift: Shift, payout: Payout? = nil) {
        self.shift = shift
        self.payout = payout
        let latest = shift.endedAt ?? .now
        latestAllowed = max(latest, payout?.receivedAt ?? latest)
        let remembered = UserDefaults.standard.string(forKey: "lastPayoutPlatform").flatMap(GigPlatform.init(rawValue:))
        _platform = State(initialValue: payout?.platform ?? remembered ?? .doorDash)
        _amount = State(initialValue: payout?.amount)
        _tip = State(initialValue: payout?.tip)
        _receivedAt = State(initialValue: payout?.receivedAt ?? latest)
        _note = State(initialValue: payout?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Platform") {
                    PlatformPicker(selection: $platform, order: GigPlatform.ordered(byUse: allPayouts.map(\.platform)))
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
                    HStack {
                        TextField("Customer tips", value: $tip, format: .currency(code: Format.currencyCode))
                            .keyboardType(.decimalPad)
                            .monospacedDigit()
                        if tip == nil {
                            Button("No tips") { tip = 0 }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Tips in this payout")
                } footer: {
                    if isTipTooLarge {
                        Text("Tips can't be more than the total payout.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Only tips customers chose to give, as shown in the app's pay breakdown. Not base pay, peak pay or promotions. Tips can lower your federal income tax (2025–2028).")
                    }
                }

                Section {
                    DatePicker("Received", selection: $receivedAt, in: shift.startedAt...latestAllowed)
                    TextField("Note (optional)", text: $note)
                }

                if let payout {
                    let canDelete = ShiftManager.canDelete(payout)
                    Section {
                        Button("Delete payout", systemImage: "trash", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .foregroundStyle(.red)
                        .confirmationDialog("Delete this payout?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                            Button("Delete payout", role: .destructive) {
                                deleteOnDisappear = true
                                dismiss()
                            }
                        }
                        .disabled(!canDelete)
                    } footer: {
                        if !canDelete {
                            Text("This is the only payout on a finished shift. Edit it, or delete the whole shift from the shift screen.")
                        }
                    }
                }
            }
            .navigationTitle(payout == nil ? "Add payout" : "Edit payout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled((amount ?? 0) <= 0 || isTipTooLarge)
                }
            }
            .onAppear { isAmountFocused = payout == nil }
            .onDisappear {
                if deleteOnDisappear, let payout {
                    shifts.deletePayout(payout)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var isTipTooLarge: Bool {
        guard let tip else { return false }
        return tip < 0 || tip > (amount ?? 0)
    }

    private func save() {
        guard let amount, amount > 0, !isTipTooLarge else { return }
        if let payout {
            shifts.updatePayout(payout, amount: amount, platform: platform, receivedAt: receivedAt, note: note, tip: tip)
        } else {
            shifts.addPayout(amount, platform: platform, receivedAt: receivedAt, note: note, tip: tip, to: shift)
            lastPlatform = platform
        }
        dismiss()
    }
}
