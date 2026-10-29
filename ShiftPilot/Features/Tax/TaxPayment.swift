import Foundation
import SwiftData

/// An estimated-tax payment the driver made (or money moved into savings) for one quarter.
@Model
final class TaxPayment {
    var amount: Decimal
    var paidAt: Date
    var year: Int
    var quarterNumber: Int
    var note: String

    init(amount: Decimal, paidAt: Date, quarter: TaxQuarter, note: String = "") {
        self.amount = amount
        self.paidAt = paidAt
        self.year = quarter.year
        self.quarterNumber = quarter.number
        self.note = note
    }

    var quarter: TaxQuarter { TaxQuarter(year: year, number: quarterNumber) }
}
