import Foundation

enum Format {
    static var currencyCode: String { Locale.current.currency?.identifier ?? "USD" }

    /// e.g. "$24.50"
    static func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode))
    }

    /// Projections and chart labels, e.g. "$8,490".
    static func wholeMoney(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0)))
    }

    /// Pump prices carry a third decimal, e.g. "$3.399".
    static func fuelPrice(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currencyCode).precision(.fractionLength(2...3)))
    }

    /// e.g. "$24.50/hr", or "—" when there isn't enough data.
    static func rate(_ amount: Decimal?, per suffix: String) -> String {
        guard let amount else { return "—" }
        return "\(money(amount))/\(suffix)"
    }

    /// e.g. "2h 14m"
    static func duration(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
