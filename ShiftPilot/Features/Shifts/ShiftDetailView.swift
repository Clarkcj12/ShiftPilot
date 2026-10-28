import SwiftUI

struct ShiftDetailView: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var isAddingPayout = false

    var body: some View {
        let snapshot = shift.snapshot()
        let payouts = shift.payouts.sorted { $0.receivedAt > $1.receivedAt }
        let trips = shift.trips.sorted { $0.startedAt > $1.startedAt }

        List {
            Section("Summary") {
                LabeledContent("Time", value: Format.duration(snapshot.duration))
                LabeledContent("Earnings", value: Format.money(snapshot.gross))
                LabeledContent("True EPH", value: Format.rate(snapshot.hourlyRate, per: "hr"))
                LabeledContent("Distance", value: unit.format(meters: snapshot.distanceMeters))
                LabeledContent("Per \(unit.abbreviation)", value: Format.rate(snapshot.earningsPerDistance(in: unit), per: unit.abbreviation))
            }

            Section("Payouts") {
                ForEach(payouts) { payout in
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
                }
                .onDelete { offsets in
                    for index in offsets {
                        shifts.deletePayout(payouts[index])
                    }
                }

                Button("Add payout", systemImage: "plus") {
                    isAddingPayout = true
                }
            }

            if !trips.isEmpty {
                Section("Trips") {
                    ForEach(trips) { TripRow(trip: $0) }
                }
            }

            if shift.isActive {
                Section {
                    Button("End shift", systemImage: "stop.fill", role: .destructive) {
                        shifts.endShift()
                    }
                }
            }
        }
        .navigationTitle(shift.startedAt.formatted(.dateTime.weekday(.wide).month().day()))
        .sheet(isPresented: $isAddingPayout) {
            AddPayoutView(shift: shift)
        }
    }
}
