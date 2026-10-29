import SwiftUI

struct ShiftDetailView: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isAddingPayout = false
    @State private var editingPayout: Payout?
    @State private var isConfirmingEnd = false
    @State private var isConfirmingDelete = false
    /// Deleted once the view is gone, so it never renders a deleted model.
    @State private var deleteOnDisappear = false

    var body: some View {
        let snapshot = shift.snapshot()
        let payouts = shift.payouts.sorted { $0.receivedAt > $1.receivedAt }
        let trips = shift.trips.sorted { $0.startedAt > $1.startedAt }

        List {
            Section("Summary") {
                LabeledContent("Time", value: Format.duration(snapshot.duration))
                LabeledContent("Earnings", value: Format.money(snapshot.gross))
                LabeledContent("True EPH", value: Format.rate(snapshot.hourlyRate, per: "hr"))
                LabeledContent("Business distance", value: unit.format(meters: snapshot.distanceMeters))
                LabeledContent("Per \(unit.abbreviation)", value: Format.rate(snapshot.earningsPerDistance(in: unit), per: unit.abbreviation))
            }

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
                            Text(Format.money(payout.amount)).monospacedDigit()
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
        .onDisappear {
            if deleteOnDisappear {
                shifts.deleteShift(shift)
            }
        }
    }
}
