import SwiftData
import SwiftUI

/// Fixes a finished shift's start and end, e.g. one left running because the app couldn't be
/// opened. Lists what happened during the shift so the driver can see when they really stopped.
struct EditShiftTimesView: View {
    let shift: Shift

    @Environment(ShiftManager.self) private var shifts
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var end: Date
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault

    init(shift: Shift) {
        self.shift = shift
        _start = State(initialValue: shift.startedAt)
        _end = State(initialValue: shift.endedAt ?? .now)
    }

    var body: some View {
        let allowed = shifts.allowedTimes(for: shift)
        let picks = Self.endSuggestions(for: shift)
        let leaving = shift.trips.filter { !Self.overlaps($0, start: start, end: end) }

        NavigationStack {
            Form {
                Section {
                    DatePicker("Started", selection: $start, in: allowed.start)
                    DatePicker("Ended", selection: $end, in: allowed.end)
                } footer: {
                    Text("Total \(Format.duration(max(0, end.timeIntervalSince(start)))). A shift can't overlap another shift or leave out one of its payouts.")
                }

                if !picks.isEmpty {
                    Section("Quick picks for the end") {
                        ForEach(picks, id: \.date) { pick in
                            Button {
                                end = pick.date.clamped(to: allowed.end)
                            } label: {
                                LabeledContent(pick.title, value: pick.date.formatted(date: .omitted, time: .shortened))
                            }
                        }
                    }
                }

                Section {
                    ForEach(Self.activity(of: shift, unit: unit), id: \.date) { item in
                        LabeledContent {
                            Text(item.date, format: .dateTime.weekday(.abbreviated).hour().minute())
                        } label: {
                            Label(item.title, systemImage: item.symbol)
                        }
                        .foregroundStyle(item.date > end || item.date < start ? .secondary : .primary)
                    }
                } header: {
                    Text("During this shift")
                } footer: {
                    if !leaving.isEmpty {
                        Text("\(leaving.count) \(leaving.count == 1 ? "trip falls" : "trips fall") outside these times and will go back to Review, so you can mark \(leaving.count == 1 ? "it" : "them") work or personal.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Shift times")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        shifts.updateTimes(of: shift, start: start, end: end)
                        dismiss()
                    }
                    .disabled(start >= end)
                }
            }
        }
    }

    struct Moment {
        var title: String
        var symbol: String = ""
        var date: Date
    }

    static func overlaps(_ trip: Trip, start: Date, end: Date) -> Bool {
        trip.startedAt < end && (trip.endedAt ?? .now) > start
    }

    /// The last payout, and the end of the drive that was under way or followed it
    /// (usually the drive home).
    static func endSuggestions(for shift: Shift) -> [Moment] {
        guard let lastPayout = shift.payouts.map(\.receivedAt).max() else { return [] }
        var picks = [Moment(title: "Last payout", date: lastPayout)]
        let driveEnd = shift.trips.compactMap(\.endedAt).filter { $0 >= lastPayout }.min()
        if let driveEnd {
            picks.append(Moment(title: "End of the drive after it", date: driveEnd))
        }
        return picks
    }

    static func activity(of shift: Shift, unit: DistanceUnit) -> [Moment] {
        let payouts = shift.payouts.map {
            Moment(title: "\($0.platform.name) \(Format.money($0.amount))", symbol: "dollarsign.circle", date: $0.receivedAt)
        }
        let trips = shift.trips.map {
            Moment(title: "Drive, \(unit.format(meters: $0.distanceMeters))", symbol: "car", date: $0.startedAt)
        }
        return (payouts + trips).sorted { $0.date < $1.date }
    }
}

private extension Date {
    func clamped(to range: ClosedRange<Date>) -> Date {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
