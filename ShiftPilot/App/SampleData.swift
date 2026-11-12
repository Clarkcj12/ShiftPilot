#if DEBUG
import Foundation
import SwiftData

/// Realistic data for UI checks and App Store screenshots. Launch with `-seedSampleData`;
/// it only seeds an empty store and is compiled out of release builds.
@MainActor
enum SampleData {
    static let launchArgument = "-seedSampleData"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    static func seedIfEmpty(_ context: ModelContext, garage: GarageStore) {
        guard (try? context.fetchCount(FetchDescriptor<Shift>())) == 0 else { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func day(_ offset: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: offset, hour: hour, minute: minute), to: today)!
        }

        let car = garage.addVehicle(units: .us)
        car.year = 2021
        car.make = "Toyota"
        car.model = "Camry"
        car.trim = "LE"
        car.plate = "8XYZ123"
        car.plateRegion = "MD"
        car.insurer = "Sample Insurance Co."
        car.insuranceExpires = calendar.date(byAdding: .day, value: 21, to: today)
        car.registrationExpires = calendar.date(byAdding: .month, value: 7, to: today)
        car.profile = VehicleProfile(units: .us, fuelEconomy: 30, fuelPrice: Decimal(string: "3.45"), wearPerDistance: Decimal(string: "0.10"))

        garage.addReading(41_200, on: calendar.date(from: DateComponents(year: calendar.component(.year, from: today), month: 1, day: 1))!, to: car)
        for (offset, odometer, gallons, cost) in [(-12, 52_010, 11.8, 40.12), (-6, 52_330, 10.4, 35.88), (-1, 52_655, 10.6, 36.04)] {
            garage.addFillUp(FillUp(date: day(offset, 8), odometer: Decimal(odometer), volume: Decimal(gallons), totalCost: Decimal(cost)), to: car)
        }

        let costPerMeter = garage.effectiveProfile(for: car).costPerMeter
        var shiftPlans: [(day: Int, start: Int, hours: Int, payouts: [(GigPlatform, Double)], miles: Double)] = [
            (-3, 11, 4, [(.doorDash, 9.5), (.doorDash, 12.25), (.uberEats, 8.75), (.doorDash, 15.0)], 38),
            (-2, 17, 5, [(.uber, 18.4), (.uber, 22.1), (.lyft, 14.6), (.uber, 26.3), (.uberEats, 11.2)], 61),
            (-1, 10, 3, [(.instacart, 24.0), (.shipt, 19.5)], 27),
        ]
        // Seven more weeks of history, four or five shifts a week, slowly picking up.
        let rotation: [(Int, Int, [(GigPlatform, Double)], Double)] = [
            (17, 4, [(.doorDash, 11), (.doorDash, 14.5), (.uberEats, 9.25)], 42),
            (11, 3, [(.instacart, 21), (.shipt, 17.5)], 31),
            (6, 3, [(.uber, 16.8), (.lyft, 13.9), (.uber, 19.4)], 48),
            (18, 3, [(.doorDash, 12.75), (.doorDash, 16), (.doorDash, 10.5)], 36),
        ]
        for offset in (5...52).reversed() where offset % 7 != 2 && offset % 7 != 5 {
            let plan = rotation[offset % rotation.count]
            let growth = 1 + Double(52 - offset) / 120
            shiftPlans.append((-offset, plan.0, plan.1, plan.2.map { ($0.0, $0.1 * growth) }, plan.3))
        }
        if calendar.component(.hour, from: .now) >= 10 {
            shiftPlans.append((0, 7, 2, [(.doorDash, 10.25), (.uberEats, 12.5)], 22))
        }
        var firstShift: Shift?
        for plan in shiftPlans {
            let shift = Shift(startedAt: day(plan.day, plan.start))
            shift.endedAt = day(plan.day, plan.start + plan.hours)
            context.insert(shift)
            firstShift = firstShift ?? shift
            for (index, payout) in plan.payouts.enumerated() {
                let received = day(plan.day, plan.start, 40 * (index + 1) % (plan.hours * 60))
                let amount = TaxCalculator.round(Decimal(payout.1 * 2))
                // Roughly a third of delivery pay is customer tips.
                let item = Payout(amount: amount, platform: payout.0, receivedAt: received, tip: TaxCalculator.round(amount * Decimal(string: "0.35")!))
                if plan.day == -2, index == 3 {
                    // A quest bonus on top of the order.
                    item.amount += 100
                    item.bonus = 100
                }
                context.insert(item)
                item.shift = shift
            }
            let trip = Trip(startedAt: day(plan.day, plan.start, 5), trigger: .carPlay)
            trip.endedAt = day(plan.day, plan.start + plan.hours, -10)
            trip.distanceMeters = plan.miles * 1609.344
            context.insert(trip)
            trip.shift = shift
            trip.vehicle = car
            trip.purpose = .business
            trip.vehicleCostPerMeter = costPerMeter
        }

        let commute = Trip(startedAt: day(0, 8), trigger: .bluetoothAudio)
        commute.endedAt = day(0, 8, 25)
        commute.distanceMeters = 9 * 1609.344
        context.insert(commute)
        commute.vehicle = car

        let tolls = Expense(date: day(-3, 12), amount: Decimal(string: "4.50")!, category: .tolls, businessUse: 1)
        tolls.shift = firstShift
        let parking = Expense(date: day(-3, 13), amount: 6, category: .parking, businessUse: 1)
        parking.shift = firstShift
        for expense in [
            tolls,
            parking,
            Expense(date: day(-10, 9), amount: 85, category: .phone, businessUse: Decimal(string: "0.6")),
            Expense(date: day(-15, 9), amount: Decimal(string: "62.18")!, category: .loanInterest, businessUse: nil),
            Expense(date: day(-20, 9), amount: 148, category: .insurance, businessUse: Decimal(string: "0.6")),
            Expense(date: day(-8, 15), amount: Decimal(string: "39.99")!, category: .supplies, businessUse: 1, note: "Insulated delivery bag"),
        ] {
            expense.vehicle = car
            context.insert(expense)
        }
        garage.save()
        Log.persistence.info("Seeded sample data")
    }
}
#endif
