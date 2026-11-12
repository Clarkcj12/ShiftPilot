import Charts
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
    @Environment(GarageStore.self) private var garage
    @Query private var expenses: [Expense]
    @State private var period: Period = .month

    var body: some View {
        let snapshots = shifts
            .filter { shift in period.cutoff.map { shift.startedAt >= $0 } ?? true }
            .map { $0.snapshot(costPerMeter: garage.costPerMeter) }
        let gross = snapshots.reduce(Decimal(0)) { $0 + $1.gross }
        let bonuses = snapshots.reduce(Decimal(0)) { $0 + $1.bonuses }
        let seconds = snapshots.reduce(0) { $0 + $1.duration }
        let everything = shifts.filter { !$0.isActive }.map { $0.snapshot(costPerMeter: garage.costPerMeter) }

        List {
            if let pace = EarningsCalculator.pace(everything) {
                Section {
                    PaceCard(pace: pace)
                }
            }

            if !everything.isEmpty {
                Section {
                    WeeklyChart(weeks: EarningsCalculator.weekly(everything))
                } header: {
                    Text("Last 8 weeks")
                }
            }

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
                breakdownSections(snapshots: snapshots, gross: gross, bonuses: bonuses, seconds: seconds, periodCosts: periodCosts)
            }
        }
        .navigationTitle("Insights")
    }

    static func best<Key>(_ rows: [EarningsBreakdown<Key>]) -> Decimal? {
        rows.compactMap(\.hourlyRate).max()
    }

    /// Business share of expenses in the period that aren't tied to a shift (insurance,
    /// phone, loan interest…); shift expenses are already in each shift's net.
    private var periodCosts: Decimal {
        expenses
            .filter { expense in expense.shift == nil && (period.cutoff.map { expense.date >= $0 } ?? true) }
            .reduce(0) { $0 + $1.snapshot.netProfitCost }
    }

    @ViewBuilder
    private func breakdownSections(snapshots: [ShiftSnapshot], gross: Decimal, bonuses: Decimal, seconds: TimeInterval, periodCosts: Decimal) -> some View {
        Section {
            ValueRow("True EPH", value: Format.rate(EarningsCalculator.hourlyRate(gross, over: seconds), per: "hr"), emphasized: true)
            if bonuses > 0 {
                ValueRow("Without rare bonuses", value: Format.rate(EarningsCalculator.hourlyRate(gross - bonuses, over: seconds), per: "hr"))
            }
            ValueRow("Earnings", value: Format.money(gross))
            if bonuses > 0 {
                ValueRow("Rare bonuses", value: Format.money(bonuses))
            }
            if let shiftNet = NetProfit.total(snapshots) {
                let net = shiftNet - periodCosts
                if periodCosts > 0 {
                    ValueRow("Other expenses", value: "−\(Format.money(TaxCalculator.round(periodCosts)))")
                }
                ValueRow("Net profit", value: Format.money(TaxCalculator.round(net)), emphasized: true)
                ValueRow("Net per hour", value: Format.rate(EarningsCalculator.hourlyRate(net, over: seconds), per: "hr"))
            }
            ValueRow("Time on shift", value: Format.duration(seconds))
            ValueRow("Shifts", value: "\(snapshots.count)")
        } header: {
            Text("Overall")
        } footer: {
            if bonuses > 0 {
                Text("Rates by platform and time of day below leave out rare bonuses, so they show what you usually make.")
            }
        }

        Section {
            let platforms = EarningsCalculator.byPlatform(snapshots)
            let bestPlatform = Self.best(platforms)
            ForEach(platforms) { row in
                BreakdownRow(gross: row.gross, bonuses: row.bonuses, seconds: row.seconds, rate: row.hourlyRate, best: bestPlatform) {
                    PlatformPill(platform: row.key)
                }
            }
        } header: {
            Text("By platform")
        } footer: {
            Text("When you run several apps in one shift, the whole shift counts toward each app that paid you.")
        }

        Section {
            let dayparts = EarningsCalculator.byDaypart(snapshots)
            let bestDaypart = Self.best(dayparts)
            ForEach(dayparts) { row in
                BreakdownRow(gross: row.gross, bonuses: row.bonuses, seconds: row.seconds, rate: row.hourlyRate, best: bestDaypart) {
                    VStack(alignment: .leading) {
                        Text(row.key.title)
                        Text(row.key.hours).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("By time of day")
        } footer: {
            Text("Each payout is spread over the time since your previous one, so log payouts as they come in for the most accurate picture.")
        }
    }
}

private struct BreakdownRow<Label: View>: View {
    let gross: Decimal
    let bonuses: Decimal
    let seconds: TimeInterval
    let rate: Decimal?
    /// The highest rate in the section, for the bar's length.
    let best: Decimal?
    @ViewBuilder let label: Label

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row
            if let fraction {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Theme.earnings.opacity(fraction >= 1 ? 1 : 0.4))
                        .frame(width: max(4, proxy.size.width * fraction))
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double? {
        guard let rate, let best, best > 0 else { return nil }
        return min(1, max(0, NSDecimalNumber(decimal: rate / best).doubleValue))
    }

    private var row: some View {
        HStack {
            label
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.rate(rate, per: "hr"))
                    .font(Theme.metric)
                Text(bonuses > 0
                     ? "\(Format.money(gross)) incl. \(Format.money(TaxCalculator.round(bonuses))) bonus · \(Format.duration(seconds))"
                     : "\(Format.money(gross)) · \(Format.duration(seconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// "On pace for": the recent weekly pace projected over a month and the rest of the year.
private struct PaceCard: View {
    let pace: EarningsPace

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("On pace for")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(Format.wholeMoney(pace.yearTotal))
                    .font(Theme.hero(40))
                Text("in \(String(pace.year)) at your last 7 days' pace")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            MetricRow(metrics: [
                MetricView(title: "Per week", value: Format.wholeMoney(pace.weekly), caption: trendText),
                MetricView(title: "Per month", value: Format.wholeMoney(pace.monthly)),
            ])
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var trendText: String? {
        guard let trend = pace.trend else { return nil }
        let percent = trend.formatted(.percent.precision(.fractionLength(0)))
        return trend >= 0 ? "Up \(percent) on the week before" : "Down \(percent.replacingOccurrences(of: "-", with: "")) on the week before"
    }
}

/// Weekly earnings, with rare bonuses stacked in a lighter shade.
private struct WeeklyChart: View {
    let weeks: [WeeklyEarnings]

    var body: some View {
        Chart {
            ForEach(weeks) { week in
                BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("Earned", NSDecimalNumber(decimal: week.base).doubleValue))
                    .foregroundStyle(by: .value("Kind", "Pay"))
                    .cornerRadius(4)
                if week.bonuses > 0 {
                    BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), y: .value("Earned", NSDecimalNumber(decimal: week.bonuses).doubleValue))
                        .foregroundStyle(by: .value("Kind", "Rare bonus"))
                        .cornerRadius(4)
                }
            }
        }
        .chartForegroundStyleScale(["Pay": Theme.earnings, "Rare bonus": Theme.bonus])
        .chartLegend(weeks.contains { $0.bonuses > 0 } ? .visible : .hidden)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: Format.currencyCode).precision(.fractionLength(0)))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 180)
        .padding(.vertical, 8)
        .accessibilityLabel("Weekly earnings")
        .accessibilityValue(weeks.map { "\($0.weekStart.formatted(.dateTime.month().day())): \(Format.money($0.total))" }.joined(separator: ", "))
    }
}
