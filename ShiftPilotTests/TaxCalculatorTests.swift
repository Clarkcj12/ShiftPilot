import Foundation
import Testing
@testable import ShiftPilot

struct TaxCalculatorTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    private let mile = TaxCalculator.metersPerMile

    @Test func mileageRateFollowsTripDate() {
        #expect(TaxTables.mileageRate(on: date(2023, 12, 31), calendar: calendar) == nil)
        #expect(TaxTables.mileageRate(on: date(2025, 3, 1), calendar: calendar) == Decimal(string: "0.70"))
        #expect(TaxTables.mileageRate(on: date(2026, 6, 30), calendar: calendar) == Decimal(string: "0.725"))
        #expect(TaxTables.mileageRate(on: date(2026, 7, 1), calendar: calendar) == Decimal(string: "0.76"))
        #expect(TaxTables.rateSummary(for: 2026) == "72.5¢/mi Jan–Jun, 76¢/mi Jul–Dec")
    }

    @Test func quartersMatchIRSPeriodsAndDueDates() {
        let quarters = TaxQuarter.all(in: 2026)
        #expect(quarters.map { $0.interval(calendar: calendar).contains(date(2026, 5, 31)) } == [false, true, false, false])
        #expect(quarters.map { $0.interval(calendar: calendar).contains(date(2026, 6, 1)) } == [false, false, true, false])
        #expect(TaxQuarter.containing(date(2026, 12, 31), calendar: calendar).number == 4)

        let due = quarters.map { calendar.dateComponents([.year, .month, .day], from: $0.dueDate(calendar: calendar)) }
        #expect(due.map(\.month) == [4, 6, 9, 1])
        #expect(due.map(\.day) == [15, 15, 15, 15])
        #expect(due.last?.year == 2027)

        // Jan 15, 2028 is a Saturday, so 2027's Q4 payment is due Monday the 17th.
        let weekend = TaxQuarter(year: 2027, number: 4).dueDate(calendar: calendar)
        #expect(calendar.component(.day, from: weekend) == 17)
    }

    @Test func deductionUsesRateInEffectOnEachTrip() {
        let estimate = TaxCalculator.estimate(
            year: 2026,
            income: [],
            mileage: [
                TaxMileage(meters: 100 * mile, date: date(2026, 6, 20)),
                TaxMileage(meters: 100 * mile, date: date(2026, 7, 20)),
            ],
            incomeTaxRate: 0,
            calendar: calendar
        )
        #expect(estimate.mileageDeduction == Decimal(string: "148.50"))
        #expect(estimate.quarters[2].mileageDeduction == Decimal(string: "148.50"))
    }

    @Test func estimatesSelfEmploymentAndIncomeTax() {
        // $1,000 earned, 100 business miles at 70¢ → $930 net.
        let estimate = TaxCalculator.estimate(
            year: 2025,
            income: [TaxIncome(amount: 1000, date: date(2025, 2, 1))],
            mileage: [TaxMileage(meters: 100 * mile, date: date(2025, 2, 1))],
            incomeTaxRate: Decimal(string: "0.12")!,
            calendar: calendar
        )
        let q1 = estimate.quarters[0]
        #expect(q1.netProfit == 930)
        // 930 × 0.9235 × 0.153 = 131.40
        #expect(q1.selfEmploymentTax == Decimal(string: "131.40"))
        // (930 − 131.40 / 2) × 0.12 = 103.72
        #expect(q1.incomeTax == Decimal(string: "103.72"))
        #expect(estimate.quarters[1...].allSatisfy { $0.setAside == 0 })
    }

    @Test func socialSecurityStopsAtWageBase() {
        let base = TaxTables.wageBase(for: 2026)
        let atCap = TaxCalculator.selfEmploymentTax(onNetProfit: base / TaxCalculator.netEarningsFactor, wageBase: base)
        let wellOver = TaxCalculator.selfEmploymentTax(onNetProfit: 2 * base / TaxCalculator.netEarningsFactor, wageBase: base)
        // Past the cap only the 2.9% Medicare part grows.
        #expect(TaxCalculator.round(wellOver - atCap) == TaxCalculator.round(base * TaxCalculator.medicareRate))
    }

    @Test func lossQuarterSetsAsideNothing() {
        let estimate = TaxCalculator.estimate(
            year: 2026,
            income: [TaxIncome(amount: 10, date: date(2026, 1, 5))],
            mileage: [TaxMileage(meters: 100 * mile, date: date(2026, 1, 5))],
            incomeTaxRate: Decimal(string: "0.12")!,
            calendar: calendar
        )
        #expect(estimate.quarters[0].netProfit < 0)
        #expect(estimate.setAside == 0)
    }
}

struct QualifiedTipsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 10, hour: 12))!
    }

    private func estimate(year: Int = 2026, gross: Decimal, tips: Decimal, rate: Decimal = Decimal(string: "0.12")!) -> TaxYearEstimate {
        TaxCalculator.estimate(
            year: year,
            income: [TaxIncome(amount: gross, date: date(year, 3))],
            mileage: [],
            tips: tips > 0 ? [TaxIncome(amount: tips, date: date(year, 3))] : [],
            incomeTaxRate: rate,
            calendar: calendar
        )
    }

    @Test func tipsLowerIncomeTaxButNotSelfEmploymentTax() {
        let without = estimate(gross: 10_000, tips: 0)
        let with = estimate(gross: 10_000, tips: 3_000)
        #expect(with.selfEmploymentTax == without.selfEmploymentTax)
        #expect(with.netProfit == without.netProfit)
        #expect(with.deductions == without.deductions)
        #expect(with.tipsDeduction == 3_000)
        #expect(without.incomeTax - with.incomeTax == 360)
    }

    @Test func deductionIsCappedAtTwentyFiveThousand() {
        #expect(estimate(gross: 100_000, tips: 40_000).tipsDeduction == 25_000)
    }

    @Test func deductionCantExceedProfit() {
        // Tips larger than profit after half of SE tax: income tax goes to zero, not negative.
        let small = estimate(gross: 1_000, tips: 1_000)
        #expect(small.tipsDeduction < 1_000)
        #expect(small.incomeTax == 0)

        let loss = TaxCalculator.estimate(
            year: 2026, income: [TaxIncome(amount: 100, date: date(2026, 3))],
            mileage: [TaxMileage(meters: 1_000 * TaxCalculator.metersPerMile, date: date(2026, 3))],
            tips: [TaxIncome(amount: 50, date: date(2026, 3))],
            incomeTaxRate: Decimal(string: "0.12")!, calendar: calendar
        )
        #expect(loss.tipsDeduction == 0)
    }

    @Test func onlyAppliesForTwentyTwentyFiveThroughTwentyTwentyEight() {
        #expect(estimate(year: 2024, gross: 10_000, tips: 1_000).tipsDeduction == 0)
        #expect(estimate(year: 2025, gross: 10_000, tips: 1_000).tipsDeduction == 1_000)
        #expect(estimate(year: 2028, gross: 10_000, tips: 1_000).tipsDeduction == 1_000)
        #expect(estimate(year: 2029, gross: 10_000, tips: 1_000).tipsDeduction == 0)
    }

    @Test func zeroBracketChangesNothing() {
        #expect(estimate(gross: 10_000, tips: 3_000, rate: 0).incomeTax == 0)
    }

    @Test func capAppliesAcrossTheYearNotPerQuarter() {
        let estimate = TaxCalculator.estimate(
            year: 2026,
            income: [TaxIncome(amount: 50_000, date: date(2026, 2)), TaxIncome(amount: 50_000, date: date(2026, 10))],
            mileage: [],
            tips: [TaxIncome(amount: 20_000, date: date(2026, 2)), TaxIncome(amount: 20_000, date: date(2026, 10))],
            incomeTaxRate: Decimal(string: "0.22")!, calendar: calendar
        )
        #expect(estimate.quarters.map(\.tipsDeduction) == [20_000, 0, 0, 5_000])
        #expect(estimate.tips == 40_000)
    }
}
