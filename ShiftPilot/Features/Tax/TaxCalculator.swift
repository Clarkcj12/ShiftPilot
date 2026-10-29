import Foundation

struct TaxIncome: Sendable {
    var amount: Decimal
    var date: Date
}

struct TaxMileage: Sendable {
    var meters: Double
    var date: Date
}

struct QuarterEstimate: Identifiable, Sendable {
    var quarter: TaxQuarter
    var gross: Decimal
    var businessMeters: Double
    var mileageDeduction: Decimal
    var selfEmploymentTax: Decimal
    var incomeTax: Decimal

    var id: Int { quarter.id }
    var netProfit: Decimal { gross - mileageDeduction }
    /// What to set aside for this period. A loss period can't make an earlier one cheaper here.
    var setAside: Decimal { max(0, selfEmploymentTax + incomeTax) }
}

struct TaxYearEstimate: Sendable {
    var year: Int
    var quarters: [QuarterEstimate]

    var gross: Decimal { quarters.reduce(0) { $0 + $1.gross } }
    var businessMeters: Double { quarters.reduce(0) { $0 + $1.businessMeters } }
    var mileageDeduction: Decimal { quarters.reduce(0) { $0 + $1.mileageDeduction } }
    var netProfit: Decimal { gross - mileageDeduction }
    var selfEmploymentTax: Decimal { quarters.reduce(0) { $0 + $1.selfEmploymentTax } }
    var incomeTax: Decimal { quarters.reduce(0) { $0 + $1.incomeTax } }
    var setAside: Decimal { quarters.reduce(0) { $0 + $1.setAside } }
}

/// Estimates mileage deductions and quarterly estimated tax for gig income.
///
/// Deliberately simple and on the safe side: self-employment tax uses the real formula,
/// but income tax is net profit (less half of SE tax) at one marginal rate the driver
/// picks, with no standard deduction, QBI deduction, credits or other income. It's a
/// set-aside guide, not a tax return.
enum TaxCalculator {
    /// Share of net profit subject to self-employment tax.
    static let netEarningsFactor = Decimal(string: "0.9235")!
    static let socialSecurityRate = Decimal(string: "0.124")!
    static let medicareRate = Decimal(string: "0.029")!
    static let metersPerMile = 1609.344

    static func estimate(
        year: Int,
        income: [TaxIncome],
        mileage: [TaxMileage],
        incomeTaxRate: Decimal,
        calendar: Calendar = .current
    ) -> TaxYearEstimate {
        let wageBase = TaxTables.wageBase(for: year)
        var cumulativeNet: Decimal = 0
        var previous = (se: Decimal(0), income: Decimal(0))

        let quarters = TaxQuarter.all(in: year).map { quarter in
            let interval = quarter.interval(calendar: calendar)
            let gross = income.filter { interval.contains($0.date) }.reduce(Decimal(0)) { $0 + $1.amount }
            let trips = mileage.filter { interval.contains($0.date) }
            let meters = trips.reduce(0) { $0 + $1.meters }
            let deduction = round(trips.reduce(Decimal(0)) { $0 + deduction(for: $1, calendar: calendar) })

            // Tax is progressive through the year (the Social Security cap), so each period
            // gets the change in year-to-date tax rather than tax on its own profit.
            cumulativeNet += gross - deduction
            let se = selfEmploymentTax(onNetProfit: cumulativeNet, wageBase: wageBase)
            let incomeTax = max(0, cumulativeNet - se / 2) * incomeTaxRate
            defer { previous = (se, incomeTax) }

            return QuarterEstimate(
                quarter: quarter,
                gross: gross,
                businessMeters: meters,
                mileageDeduction: deduction,
                selfEmploymentTax: round(se - previous.se),
                incomeTax: round(incomeTax - previous.income)
            )
        }
        return TaxYearEstimate(year: year, quarters: quarters)
    }

    static func deduction(for trip: TaxMileage, calendar: Calendar = .current) -> Decimal {
        guard let rate = TaxTables.mileageRate(on: trip.date, calendar: calendar) else { return 0 }
        return Decimal(trip.meters / metersPerMile) * rate
    }

    /// 15.3% on 92.35% of net profit: 12.4% Social Security up to the wage base, 2.9% Medicare on all.
    /// (The extra 0.9% Medicare tax over $200k isn't included.)
    static func selfEmploymentTax(onNetProfit net: Decimal, wageBase: Decimal) -> Decimal {
        let earnings = max(0, net) * netEarningsFactor
        return min(earnings, wageBase) * socialSecurityRate + earnings * medicareRate
    }

    static func round(_ value: Decimal) -> Decimal {
        var value = value
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }
}
