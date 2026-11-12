import SwiftUI

struct ShiftDetailView: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(\.dismiss) private var dismiss
    @Environment(GarageStore.self) private var garage
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isAddingPayout = false
    @State private var editingPayout: Payout?
    @State private var isAddingExpense = false
    @State private var editingExpense: Expense?
    @State private var isConfirmingEnd = false
    @State private var isConfirmingDelete = false
    @State private var isEditingTimes = false
    /// Deleted once the view is gone, so it never renders a deleted model.
    @State private var deleteOnDisappear = false

    var body: some View {
        let snapshot = shift.snapshot(costPerMeter: garage.costPerMeter)
        let payouts = shift.payouts.sorted { $0.receivedAt > $1.receivedAt }
        let trips = shift.trips.sorted { $0.startedAt > $1.startedAt }

        List {
            Section {
                LabeledContent("Time", value: Format.duration(snapshot.duration))
                if !shift.isActive {
                    Button {
                        isEditingTimes = true
                    } label: {
                        LabeledContent("Hours", value: Self.timeRange(shift))
                    }
                }
                LabeledContent("Earnings", value: Format.money(snapshot.gross))
                LabeledContent("True EPH", value: Format.rate(snapshot.hourlyRate, per: "hr"))
                if snapshot.bonuses > 0 {
                    LabeledContent("Without rare bonuses", value: Format.rate(EarningsCalculator.hourlyRate(snapshot.gross - snapshot.bonuses, over: snapshot.duration), per: "hr"))
                }
                LabeledContent("Business distance", value: unit.format(meters: snapshot.distanceMeters))
                LabeledContent("Per \(unit.abbreviation)", value: Format.rate(snapshot.earningsPerDistance(in: unit), per: unit.abbreviation))
            } header: {
                Text("Summary")
            } footer: {
                if !shift.isActive, snapshot.duration >= Self.longShift {
                    Text("This shift ran \(Format.duration(snapshot.duration)). If it was left running, tap Hours to set when you really stopped.")
                        .foregroundStyle(.orange)
                } else if !shift.isActive {
                    Text("Tap Hours to change when the shift started or ended.")
                }
            }

            NetProfitSection(snapshot: snapshot)

            Section {
                ForEach(payouts) { payout in
                    Button {
                        editingPayout = payout
                    } label: {
                        HStack {
                            PlatformPill(platform: payout.platform)
                            VStack(alignment: .leading) {
                                Text(payout.receivedAt, format: .dateTime.hour().minute())
                                if !payout.note.isEmpty {
                                    Text(payout.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(Format.money(payout.amount)).monospacedDigit()
                                if let tip = payout.tip, tip > 0 {
                                    Text("\(Format.money(tip)) tips").font(.caption).foregroundStyle(.secondary)
                                }
                                if let bonus = payout.bonus, bonus > 0 {
                                    Text("\(Format.money(bonus)) rare bonus").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .deleteDisabled(!ShiftManager.canDelete(payout))
                }
                .onDelete { offsets in
                    for index in offsets {
                        shifts.deletePayout(payouts[index])
                    }
                }

                Button("Add payout", systemImage: "plus") {
                    isAddingPayout = true
                }
            } header: {
                Text("Payouts")
            } footer: {
                if !payouts.isEmpty {
                    Text("Tap a payout to edit it, or swipe left to delete it.")
                }
            }

            Section {
                ForEach(shift.expenses.sorted { $0.date > $1.date }) { expense in
                    Button {
                        editingExpense = expense
                    } label: {
                        ExpenseRow(expense: expense).contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                Button("Add tolls, parking or other", systemImage: "plus") {
                    isAddingExpense = true
                }
            } header: {
                Text("Expenses")
            } footer: {
                if !shift.expenses.isEmpty {
                    Text("Business tolls and parking are deducted on top of your mileage and lower this shift's net profit.")
                }
            }

            if !trips.isEmpty {
                Section("Trips") {
                    ForEach(trips) { TripLink(trip: $0) }
                }
            }

            Section {
                if shift.isActive {
                    Button("End shift", systemImage: "stop.fill", role: .destructive) {
                        isConfirmingEnd = true
                    }
                    .foregroundStyle(.red)
                    .endShiftDialog(shift: shift, isPresented: $isConfirmingEnd, isAddingPayout: $isAddingPayout)
                }
                Button("Delete shift", systemImage: "trash", role: .destructive) {
                    isConfirmingDelete = true
                }
                .foregroundStyle(.red)
                .confirmationDialog("Delete this shift?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete shift", role: .destructive) {
                        deleteOnDisappear = true
                        dismiss()
                    }
                } message: {
                    Text("Its payouts are deleted too. Trips stay in your trip log.")
                }
            }
        }
        .navigationTitle(shift.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
        .sheet(isPresented: $isAddingPayout) {
            AddPayoutView(shift: shift)
        }
        .sheet(item: $editingPayout) { payout in
            AddPayoutView(shift: shift, payout: payout)
        }
        .sheet(isPresented: $isEditingTimes) {
            EditShiftTimesView(shift: shift)
        }
        .sheet(isPresented: $isAddingExpense) {
            ExpenseEditorView(shift: shift)
        }
        .sheet(item: $editingExpense) { expense in
            ExpenseEditorView(expense: expense)
        }
        .onDisappear {
            if deleteOnDisappear {
                shifts.deleteShift(shift)
            }
        }
    }

    /// Longer than any real working day; most likely left running.
    static let longShift: TimeInterval = 14 * 60 * 60

    static func timeRange(_ shift: Shift) -> String {
        let start = shift.startedAt
        guard let end = shift.endedAt else { return start.formatted(date: .omitted, time: .shortened) }
        let endText = Calendar.current.isDate(start, inSameDayAs: end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        return "\(start.formatted(date: .omitted, time: .shortened)) – \(endText)"
    }
}
