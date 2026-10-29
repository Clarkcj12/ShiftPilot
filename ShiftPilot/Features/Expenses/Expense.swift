import Foundation
import SwiftData

/// How a category is handled under the IRS standard mileage rate (Pub 463), for a
/// self-employed driver.
enum ExpenseTaxTreatment: Sendable {
    /// Deductible on top of the mileage rate (business share only).
    case addedDeduction
    /// Already part of the mileage rate; can't be deducted separately.
    case coveredByMileageRate
    /// Fines and penalties (IRC §162(f)).
    case neverDeductible
    /// Not counted; the driver should ask a tax professional.
    case notCounted
}

/// How the business share of a category is entered.
enum BusinessUseKind: Sendable {
    /// "For gig work" on/off.
    case toggle
    /// A percentage, never assumed to be 100%.
    case percentage
}

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable, Sendable {
    case tolls, parking, fuel, maintenance, tires, carWash, insurance, registration
    case loanInterest, propertyTax, phone, supplies, fines, other

    var id: Self { self }

    var name: String {
        switch self {
        case .tolls: "Tolls"
        case .parking: "Parking"
        case .fuel: "Fuel"
        case .maintenance: "Maintenance & repairs"
        case .tires: "Tires"
        case .carWash: "Car wash"
        case .insurance: "Insurance"
        case .registration: "Registration & fees"
        case .loanInterest: "Car loan interest"
        case .propertyTax: "Vehicle property tax"
        case .phone: "Phone & data"
        case .supplies: "Gig supplies"
        case .fines: "Tickets & fines"
        case .other: "Other"
        }
    }

    var symbol: String {
        switch self {
        case .tolls: "road.lanes"
        case .parking: "parkingsign"
        case .fuel: "fuelpump"
        case .maintenance: "wrench.and.screwdriver"
        case .tires: "circle.circle"
        case .carWash: "drop"
        case .insurance: "shield"
        case .registration: "doc.text"
        case .loanInterest: "percent"
        case .propertyTax: "building.columns"
        case .phone: "iphone"
        case .supplies: "bag"
        case .fines: "exclamationmark.octagon"
        case .other: "ellipsis.circle"
        }
    }

    var taxTreatment: ExpenseTaxTreatment {
        switch self {
        case .tolls, .parking, .loanInterest, .propertyTax, .phone, .supplies: .addedDeduction
        case .fuel, .maintenance, .tires, .carWash, .insurance, .registration: .coveredByMileageRate
        case .fines: .neverDeductible
        case .other: .notCounted
        }
    }

    /// Fuel, maintenance and tires are what the per-mile running cost models, so the
    /// receipts don't reduce net profit again.
    var isInPerMileCost: Bool {
        switch self {
        case .fuel, .maintenance, .tires: true
        default: false
        }
    }

    var businessUseKind: BusinessUseKind {
        switch self {
        case .loanInterest, .propertyTax, .phone, .insurance, .registration: .percentage
        default: .toggle
        }
    }

    /// Typically incurred during a shift, so it links to the shift it happened in.
    var linksToShift: Bool {
        switch self {
        case .tolls, .parking, .fines, .carWash: true
        default: false
        }
    }

    /// Default for the "For gig work" toggle: shift-linked costs (tolls, parking…) count as
    /// work only when a shift was running; other toggle categories (supplies) default to work.
    func defaultsToWork(duringShift: Bool) -> Bool {
        duringShift || !linksToShift
    }

    /// Extra guidance shown under the amount.
    var hint: String? {
        switch self {
        case .loanInterest: "Interest only, from your loan statement. Not your whole car payment."
        case .propertyTax: "The yearly value-based tax on the car, if your state charges one."
        case .phone: "Your monthly bill. Enter the share you use for gig apps below."
        case .registration: "Flat registration fees are covered by the mileage rate."
        case .parking, .tolls: "Only parking and tolls while working count, not your commute."
        default: nil
        }
    }
}

@Model
final class Expense {
    var date: Date
    var amount: Decimal
    var categoryRawValue: String
    /// Business share, 0–1. nil means not answered yet: nothing is deducted or
    /// subtracted until it is.
    var businessUse: Decimal?
    var note: String = ""
    var vehicle: Vehicle?
    var shift: Shift?

    init(date: Date, amount: Decimal, category: ExpenseCategory, businessUse: Decimal?, note: String = "") {
        self.date = date
        self.amount = amount
        self.categoryRawValue = category.rawValue
        self.businessUse = businessUse
        self.note = note
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    var snapshot: ExpenseSnapshot {
        ExpenseSnapshot(date: date, amount: amount, category: category, businessUse: businessUse, isLinkedToShift: shift != nil)
    }
}

/// Plain-value expense for the tax and profit math.
struct ExpenseSnapshot: Sendable, Equatable {
    var date: Date
    var amount: Decimal
    var category: ExpenseCategory
    var businessUse: Decimal?
    var isLinkedToShift: Bool = false

    var needsBusinessUse: Bool { businessUse == nil }

    /// The business share of the amount.
    var businessAmount: Decimal {
        amount * min(1, max(0, businessUse ?? 0))
    }

    /// What adds to deductions under the standard mileage rate.
    var deductibleAmount: Decimal {
        category.taxTreatment == .addedDeduction ? businessAmount : 0
    }

    /// What reduces net profit; fuel, maintenance and tires are already in the per-mile cost.
    var netProfitCost: Decimal {
        category.isInPerMileCost ? 0 : businessAmount
    }
}
