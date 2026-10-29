import SwiftData
import SwiftUI

/// Mileage deduction and quarterly estimated tax for one tax year.
struct TaxVaultView: View {
    @Query private var payouts: [Payout]
    @Query private var trips: [Trip]
    @Query(sort: \TaxPayment.paidAt) private var payments: [TaxPayment]
    @AppStorage(TaxSettings.incomeTaxRateKey) private var incomeTaxPercent = TaxSettings.defaultIncomeTaxPercent
    @AppStorage(DistanceUnit.storageKey) private var unit: DistanceUnit = .localeDefault
    @State private var year = Calendar.current.component(.year, from: .now)

    var body: some View {
        let estimate = TaxVault.estimate(year: year, payouts: payouts, trips: trips, incomeTaxPercent: incomeTaxPercent)
        let paid = TaxVault.paid(payments, in: year)
        let paidTotal = paid.values.reduce(0, +)
        let needsReview = trips.filter { $0.purpose == nil && !$0.isActive && Calendar.current.component(.year, from: $0.startedAt) == year }.count

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(Format.money(estimate.setAside))
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("Estimated tax to set aside for \(String(year))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack(alignment: .top) {
                        ShiftMetric(title: "Paid", value: Format.money(paidTotal))
                        ShiftMetric(title: "Remaining", value: Format.money(max(0, estimate.setAside - paidTotal)))
                        ShiftMetric(title: "Deduction", value: Format.money(estimate.mileageDeduction))
                    }
                }
                .padding(.vertical, 6)
            }

            if needsReview > 0 {
                Section {
                    NavigationLink {
                        TripListView(filter: .review)
                    } label: {
                        Label(
                            "\(needsReview) \(needsReview == 1 ? "trip isn't" : "trips aren't") counted until reviewed",
                            systemImage: "questionmark.circle.fill"
                        )
                        .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                ForEach(estimate.quarters) { quarter in
                    NavigationLink {
                        TaxQuarterView(estimate: quarter)
                    } label: {
                        QuarterRow(estimate: quarter, paid: paid[quarter.quarter.number] ?? 0)
                    }
                }
            } header: {
                Text("Quarterly payments")
            } footer: {
                Text("Pay estimated tax at irs.gov/payments (IRS Direct Pay), then record it here.")
            }

            Section {
                LabeledContent("Earnings", value: Format.money(estimate.gross))
                LabeledContent("Business distance", value: unit.format(meters: estimate.businessMeters))
                LabeledContent("Mileage deduction", value: Format.money(estimate.mileageDeduction))
                LabeledContent("Net profit", value: Format.money(estimate.netProfit))
                LabeledContent("Self-employment tax", value: Format.money(estimate.selfEmploymentTax))
                LabeledContent("Income tax (\(incomeTaxPercent)%)", value: Format.money(estimate.incomeTax))
            } header: {
                Text("\(String(year)) breakdown")
            } footer: {
                Text(rateFooter)
            }

            Section {
                Picker("Federal tax bracket", selection: $incomeTaxPercent) {
                    ForEach(TaxSettings.brackets, id: \.self) { Text("\($0)%").tag($0) }
                }
            } footer: {
                Text("Your top federal income tax rate, counting all your income. If you're not sure, 12% covers most part-time drivers. State tax isn't included.")
            }

            Section {
                Text(TaxSettings.disclaimer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Tax Vault")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var years: [Int] {
        let calendar = Calendar.current
        let current = calendar.component(.year, from: .now)
        let withData = payouts.map { calendar.component(.year, from: $0.receivedAt) }
            + trips.map { calendar.component(.year, from: $0.startedAt) }
        return Set(withData + [current]).sorted(by: >)
    }

    private var rateFooter: String {
        let rates = "IRS business mileage rate for \(String(year)): \(TaxTables.rateSummary(for: year))."
        guard TaxTables.hasPublishedRate(for: year) else {
            return rates + " The \(String(year)) rate isn't in the app yet, so the latest known rate is used."
        }
        return rates + " Only trips marked business count."
    }
}

private struct QuarterRow: View {
    let estimate: QuarterEstimate
    let paid: Decimal

    var body: some View {
        let status = TaxVault.status(of: estimate, paid: paid)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(estimate.quarter.title) · \(estimate.quarter.months)")
                Text("Due \(estimate.quarter.dueDate().formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.money(estimate.setAside))
                    .monospacedDigit()
                if let status {
                    Text(status.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(status.color)
                        .background(status.color.opacity(0.15), in: .capsule)
                }
            }
        }
    }
}

enum TaxSettings {
    static let incomeTaxRateKey = "incomeTaxRatePercent"
    static let defaultIncomeTaxPercent = 12
    /// 2026 federal brackets.
    static let brackets = [0, 10, 12, 22, 24, 32, 35, 37]
    static let disclaimer = "Estimates only, not tax advice. ShiftPilot uses the IRS standard mileage rate and a simplified income tax estimate without your standard deduction, credits or other income, so it usually sets aside a little more than you'll owe. Check with a tax professional or the IRS Form 1040-ES worksheet."
}

/// Glue between SwiftData models and the pure `TaxCalculator`.
enum TaxVault {
    enum Status {
        case paid, overdue, dueSoon(days: Int), upcoming, nothingDue

        var label: String {
            switch self {
            case .paid: "Paid"
            case .overdue: "Overdue"
            case .dueSoon(let days): days == 0 ? "Due today" : "Due in \(days)d"
            case .upcoming: "Upcoming"
            case .nothingDue: "Nothing due"
            }
        }

        var color: Color {
            switch self {
            case .paid: .green
            case .overdue: .red
            case .dueSoon: .orange
            case .upcoming, .nothingDue: .secondary
            }
        }
    }

    static func estimate(year: Int, payouts: [Payout], trips: [Trip], incomeTaxPercent: Int) -> TaxYearEstimate {
        TaxCalculator.estimate(
            year: year,
            income: payouts.map { TaxIncome(amount: $0.amount, date: $0.receivedAt) },
            mileage: trips
                .filter { $0.purpose == .business && !$0.isActive }
                .map { TaxMileage(meters: $0.distanceMeters, date: $0.startedAt) },
            incomeTaxRate: Decimal(incomeTaxPercent) / 100
        )
    }

    /// Paid amount by quarter number.
    static func paid(_ payments: [TaxPayment], in year: Int) -> [Int: Decimal] {
        payments.filter { $0.year == year }
            .reduce(into: [:]) { $0[$1.quarterNumber, default: 0] += $1.amount }
    }

    /// nil while the period hasn't started and nothing's been earned yet.
    static func status(of estimate: QuarterEstimate, paid: Decimal, now: Date = .now, calendar: Calendar = .current) -> Status? {
        let interval = estimate.quarter.interval(calendar: calendar)
        if paid > 0, paid >= estimate.setAside { return .paid }
        if estimate.setAside == 0 {
            return interval.end <= now ? .nothingDue : (interval.start <= now ? .upcoming : nil)
        }
        let due = calendar.startOfDay(for: estimate.quarter.dueDate(calendar: calendar))
        let today = calendar.startOfDay(for: now)
        if today > due { return .overdue }
        let days = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        return days <= 30 ? .dueSoon(days: days) : .upcoming
    }
}
