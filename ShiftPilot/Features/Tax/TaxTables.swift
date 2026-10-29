import Foundation

/// Published IRS and SSA figures. Update once a year (the IRS announces next year's
/// mileage rate in December) and whenever the IRS revises a rate mid-year.
enum TaxTables {
    struct RatePeriod: Sendable {
        var year: Int
        var month: Int
        var day: Int
        /// Dollars per business mile.
        var rate: Decimal
    }

    /// Business standard mileage rates. Each applies from its start date until the next one.
    /// Sources: IRS Notice 2026-10; Announcement 2026-11 (76¢ from July 1, 2026).
    static let mileageRates: [RatePeriod] = [
        RatePeriod(year: 2024, month: 1, day: 1, rate: Decimal(string: "0.67")!),
        RatePeriod(year: 2025, month: 1, day: 1, rate: Decimal(string: "0.70")!),
        RatePeriod(year: 2026, month: 1, day: 1, rate: Decimal(string: "0.725")!),
        RatePeriod(year: 2026, month: 7, day: 1, rate: Decimal(string: "0.76")!),
    ]

    /// Social Security wage base: the 12.4% part of self-employment tax stops here.
    static let socialSecurityWageBase: [Int: Decimal] = [
        2024: 168_600,
        2025: 176_100,
        2026: 184_500,
    ]

    static var latestRateYear: Int { mileageRates.map(\.year).max() ?? 0 }

    /// The rate for a trip on `date`, or nil before the table starts. Years after the
    /// table use its last rate; check `hasPublishedRate(for:)` to flag that.
    static func mileageRate(on date: Date, calendar: Calendar = .current) -> Decimal? {
        let periods = mileageRates.compactMap { period -> (start: Date, rate: Decimal)? in
            calendar.date(from: DateComponents(year: period.year, month: period.month, day: period.day))
                .map { ($0, period.rate) }
        }
        return periods.last { $0.start <= date }?.rate
    }

    /// The rate on `date` as shown to drivers, e.g. "76¢/mi".
    static func rateLabel(on date: Date, calendar: Calendar = .current) -> String {
        guard let rate = mileageRate(on: date, calendar: calendar) else { return "" }
        return "\((rate * 100).formatted(.number.precision(.fractionLength(0...1))))¢/mi"
    }

    static func hasPublishedRate(for year: Int) -> Bool {
        year <= latestRateYear
    }

    static func wageBase(for year: Int) -> Decimal {
        socialSecurityWageBase[year] ?? socialSecurityWageBase[socialSecurityWageBase.keys.max() ?? year] ?? 0
    }

    /// Human-readable rates for a year, e.g. "72.5¢/mi Jan–Jun, 76¢/mi Jul–Dec".
    static func rateSummary(for year: Int) -> String {
        let inYear = mileageRates.filter { $0.year == year }
        let periods = inYear.isEmpty ? Array(mileageRates.suffix(1)) : inYear
        let months = Calendar.current.shortMonthSymbols
        return periods.enumerated().map { index, period in
            let cents = (period.rate * 100).formatted(.number.precision(.fractionLength(0...1)))
            guard periods.count > 1 else { return "\(cents)¢/mi" }
            let endMonth = index + 1 < periods.count ? periods[index + 1].month - 1 : 12
            return "\(cents)¢/mi \(months[period.month - 1])–\(months[endMonth - 1])"
        }
        .joined(separator: ", ")
    }
}

/// One of the IRS's four estimated-tax periods. They aren't calendar quarters:
/// Jan–Mar, Apr–May, Jun–Aug and Sep–Dec.
struct TaxQuarter: Identifiable, Hashable, Sendable {
    var year: Int
    var number: Int

    var id: Int { year * 10 + number }
    var title: String { "Q\(number)" }

    static func all(in year: Int) -> [TaxQuarter] {
        (1...4).map { TaxQuarter(year: year, number: $0) }
    }

    static func containing(_ date: Date, calendar: Calendar = .current) -> TaxQuarter {
        let year = calendar.component(.year, from: date)
        return all(in: year).first { $0.interval(calendar: calendar).contains(date) } ?? TaxQuarter(year: year, number: 4)
    }

    /// First month of each period; the next period's first month ends it.
    private var startMonth: Int { [1, 4, 6, 9][number - 1] }

    var months: String {
        ["Jan–Mar", "Apr–May", "Jun–Aug", "Sep–Dec"][number - 1]
    }

    func interval(calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1))!
        let end = number == 4
            ? calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1))!
            : calendar.date(from: DateComponents(year: year, month: [4, 6, 9][number - 1], day: 1))!
        return DateInterval(start: start, end: end)
    }

    /// Apr 15, Jun 15, Sep 15 and Jan 15 of the next year, moved to Monday when they land on
    /// a weekend. (A federal holiday can push it one more day; the IRS form lists exact dates.)
    func dueDate(calendar: Calendar = .current) -> Date {
        let components = number == 4
            ? DateComponents(year: year + 1, month: 1, day: 15)
            : DateComponents(year: year, month: [4, 6, 9][number - 1], day: 15)
        var due = calendar.date(from: components)!
        while calendar.isDateInWeekend(due) {
            due = calendar.date(byAdding: .day, value: 1, to: due)!
        }
        return due
    }
}
