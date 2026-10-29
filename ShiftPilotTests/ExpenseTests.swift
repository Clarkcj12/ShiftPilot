import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

struct ExpenseTreatmentTests {
    private func expense(_ category: ExpenseCategory, _ amount: Decimal, use: Decimal?) -> ExpenseSnapshot {
        ExpenseSnapshot(date: .now, amount: amount, category: category, businessUse: use)
    }

    @Test func treatmentsFollowStandardMileageRules() {
        for category: ExpenseCategory in [.tolls, .parking, .loanInterest, .propertyTax, .phone, .supplies] {
            #expect(category.taxTreatment == .addedDeduction, "\(category)")
        }
        for category: ExpenseCategory in [.fuel, .maintenance, .tires, .carWash, .insurance, .registration] {
            #expect(category.taxTreatment == .coveredByMileageRate, "\(category)")
        }
        #expect(ExpenseCategory.fines.taxTreatment == .neverDeductible)
        // Percentages are never a toggle that could silently mean 100%.
        #expect(ExpenseCategory.phone.businessUseKind == .percentage)
        #expect(ExpenseCategory.loanInterest.businessUseKind == .percentage)
    }

    @Test func deductibleAmountUsesBusinessShare() {
        #expect(expense(.phone, 80, use: Decimal(string: "0.6")).deductibleAmount == 48)
        #expect(expense(.tolls, 5, use: 1).deductibleAmount == 5)
        #expect(expense(.parking, 5, use: 0).deductibleAmount == 0)
        // Unanswered business share deducts nothing.
        #expect(expense(.loanInterest, 60, use: nil).deductibleAmount == 0)
        #expect(expense(.loanInterest, 60, use: nil).needsBusinessUse)
        // Covered and fines never deduct, but fines still cost money.
        #expect(expense(.insurance, 150, use: 1).deductibleAmount == 0)
        #expect(expense(.fines, 40, use: 1).deductibleAmount == 0)
        #expect(expense(.fines, 40, use: 1).netProfitCost == 40)
    }

    @Test func forWorkDefaultFollowsShiftAndCategory() {
        #expect(ExpenseCategory.tolls.defaultsToWork(duringShift: true))
        #expect(!ExpenseCategory.tolls.defaultsToWork(duringShift: false))
        #expect(!ExpenseCategory.parking.defaultsToWork(duringShift: false))
        // Supplies aren't tied to a shift, so they default to work either way.
        #expect(ExpenseCategory.supplies.defaultsToWork(duringShift: false))
    }

    @Test func perMileCategoriesDontLowerNetProfitTwice() {
        #expect(expense(.fuel, 40, use: 1).netProfitCost == 0)
        #expect(expense(.maintenance, 600, use: 1).netProfitCost == 0)
        #expect(expense(.insurance, 150, use: Decimal(string: "0.5")).netProfitCost == 75)
    }

    @Test func deductionsLowerTaxInTheirQuarter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let feb = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let income = [TaxIncome(amount: 1000, date: feb)]
        let base = TaxCalculator.estimate(year: 2026, income: income, mileage: [], incomeTaxRate: 0, calendar: calendar)
        let withTolls = TaxCalculator.estimate(year: 2026, income: income, mileage: [], deductions: [TaxIncome(amount: 100, date: feb)], incomeTaxRate: 0, calendar: calendar)

        #expect(withTolls.quarters[0].otherDeductions == 100)
        #expect(withTolls.netProfit == 900)
        // 100 × 0.9235 × 0.153 ≈ $14.13 less SE tax.
        #expect(base.selfEmploymentTax - withTolls.selfEmploymentTax == Decimal(string: "14.13"))
    }
}

@MainActor
struct ExpenseStoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Trip.self, TripPoint.self, Shift.self, Payout.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func garage(_ context: ModelContext, _ name: String) -> GarageStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return GarageStore(context: context, defaults: defaults)
    }

    @Test func shiftExpensesLowerShiftNetProfit() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift(at: .now.addingTimeInterval(-3600))
        let shift = try #require(shifts.activeShift)
        shifts.addPayout(50, platform: .doorDash, receivedAt: .now, to: shift)

        let tolls = Expense(date: .now, amount: 5, category: .tolls, businessUse: 1)
        context.insert(tolls)
        tolls.shift = shift
        #expect(shift.snapshot(costPerMeter: 0).netProfit == 45)
    }

    @Test func linksExpenseToShiftRunningAtThatTime() throws {
        let context = try makeContext()
        let store = garage(context, #function)
        let shifts = ShiftManager(context: context)
        shifts.startShift(at: .now.addingTimeInterval(-3600))
        #expect(store.shift(containing: .now.addingTimeInterval(-60)) == shifts.activeShift)
        #expect(store.shift(containing: .now.addingTimeInterval(-7200)) == nil)
    }

    @Test func retiringKeepsRecordsAndPromotesNextVehicle() throws {
        let context = try makeContext()
        let store = garage(context, #function)
        let old = store.addVehicle(units: .us)
        let new = store.addVehicle(units: .us)
        store.addFillUp(FillUp(date: .now, odometer: 1000, volume: 10, totalCost: 35), to: old)

        store.retire(old)
        #expect(old.isRetired)
        #expect(store.current == new)
        #expect(old.fillUps.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<FillUp>()) == 1)

        store.reinstate(old)
        #expect(!old.isRetired)
        #expect(store.current == new)
    }

    @Test func suggestsBusinessShareFromMileage() throws {
        let context = try makeContext()
        let store = garage(context, #function)
        let car = store.addVehicle(units: .us)
        let year = Calendar.current.component(.year, from: .now)
        let jan = Calendar.current.date(from: DateComponents(year: year, month: 1, day: 2))!
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: .now))!
        let tripDay = yesterday.addingTimeInterval(12 * 3600)
        #expect(car.suggestedBusinessUse(in: year) == nil)

        let trip = Trip(startedAt: tripDay, trigger: .carPlay)
        trip.distanceMeters = 600 * 1609.344
        context.insert(trip)
        trip.vehicle = car
        trip.purpose = .business

        // A January reading predates tracking: 600 of 20,000 miles would be a misleading 3%.
        store.addReading(10_000, on: jan, to: car)
        store.addReading(30_000, on: .now, to: car)
        #expect(car.suggestedBusinessUse(in: year) == nil)

        // Readings around the tracked trip give the real share.
        store.addReading(29_000, on: tripDay.addingTimeInterval(-3600), to: car)
        #expect(car.suggestedBusinessUse(in: year) == Decimal(string: "0.6"))
    }
}
