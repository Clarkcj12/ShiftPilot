import SwiftData
import SwiftUI

/// Which platform and which time of day pays best.
struct EarningsInsightsView: View {
    enum Period: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        case all = "All time"

        var id: Self { self }

        var cutoff: Date? {
            switch self {
            case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
            case .month: Calendar.current.date(byAdding: .day, value: -30, to: .now)
            case .all: nil
            }
        }
    }

    @Query(sort: \Shift.startedAt, order: .reverse) private var shifts: [Shift]
    @Environment(VehicleStore.self) private var vehicle
    @State private var period: Period = .month

    var body: some View {
        let snapshots = shifts
            .filter { shift in period.cutoff.map { shift.startedAt >= $0 } ?? true }
            .map { $0.snapshot(costPerMeter: vehicle.costPerMeter) }
        let gross = snapshots.reduce(Decimal(0)) { $0 + $1.gross }
        let seconds = snapshots.reduce(0) { $0 + $1.duration }

        List {
            Section {
                Picker("Period", selection: $period) {
                    ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if snapshots.isEmpty {
                Section {
                    ContentUnavailableView("No shifts in this period", systemImage: "chart.bar", description: Text("Shift earnings will appear here."))
                        .listRowBackground(Color.clear)
                }
            } else {
                breakdownSections(snapshots: snapshots, gross: gross, seconds: seconds)
            }
        }
        .navigationTitle("Insights")
    }

    @ViewBuilder
    private func breakdownSections(snapshots: [ShiftSnapshot], gross: Decimal, seconds: TimeInterval) -> some View {
        Section("Overall") {
            LabeledContent("True EPH", value: Format.rate(EarningsCalculator.hourlyRate(gross, over: seconds), per: "hr"))
            LabeledContent("Earnings", value: Format.money(gross))
            if let net = NetProfit.total(snapshots) {
                LabeledContent("Net profit", value: Format.money(net))
                LabeledContent("Net per hour", value: Format.rate(EarningsCalculator.hourlyRate(net, over: seconds), per: "hr"))
            }
            LabeledContent("Time on shift", value: Format.duration(seconds))
            LabeledContent("Shifts", value: "\(snapshots.count)")
        }

        Section {
            ForEach(EarningsCalculator.byPlatform(snapshots)) { row in
                BreakdownRow(gross: row.gross, seconds: row.seconds, rate: row.hourlyRate) {
                    PlatformPill(platform: row.key)
                }
            }
        } header: {
            Text("By platform")
        } footer: {
            Text("When you run several apps in one shift, the whole shift counts toward each app that paid you.")
        }

        Section {
            ForEach(EarningsCalculator.byDaypart(snapshots)) { row in
                BreakdownRow(gross: row.gross, seconds: row.seconds, rate: row.hourlyRate) {
                    VStack(alignment: .leading) {
                        Text(row.key.title)
                        Text(row.key.hours).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("By time of day")
        } footer: {
            Text("Pay is grouped by when each payout was received, so log payouts as they come in for the most accurate picture.")
        }
    }
}

private struct BreakdownRow<Label: View>: View {
    let gross: Decimal
    let seconds: TimeInterval
    let rate: Decimal?
    @ViewBuilder let label: Label

    var body: some View {
        HStack {
            label
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.rate(rate, per: "hr"))
                    .font(.headline.monospacedDigit())
                Text("\(Format.money(gross)) · \(Format.duration(seconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
