import Foundation
import Testing
@testable import ShiftPilot

struct FuelEconomyTests {
    private func fill(_ odometer: Decimal, _ volume: Decimal, cost: Decimal = 40, full: Bool = true, day: Int = 1) -> FillUpSnapshot {
        FillUpSnapshot(date: Date(timeIntervalSince1970: Double(day) * 86_400), odometer: odometer, volume: volume, totalCost: cost, isFullTank: full)
    }

    @Test func needsTwoFullFills() {
        #expect(FuelEconomyCalculator.measured([fill(1000, 10)], units: .us) == nil)
        #expect(FuelEconomyCalculator.measured([fill(1000, 10), fill(1250, 10, full: false)], units: .us) == nil)
    }

    @Test func fullToFullIncludesPartialTopUps() throws {
        // 300 miles on 6 + 4 gallons after the first full fill = 30 MPG.
        let measured = try #require(FuelEconomyCalculator.measured(
            [fill(1000, 12), fill(1150, 6, full: false), fill(1300, 4)],
            units: .us
        ))
        #expect(measured.value == 30)
        #expect(measured.intervals == 1)
    }

    @Test func metricIsLitersPer100Km() throws {
        // 500 km on 40 L = 8 L/100 km.
        let measured = try #require(FuelEconomyCalculator.measured([fill(20_000, 35), fill(20_500, 40)], units: .metric))
        #expect(measured.value == 8)
    }

    @Test func usesOnlyRecentIntervals() throws {
        // Six 25 MPG tanks, then five 30 MPG ones: only the last five count.
        var fills = [fill(0, 10)]
        var odometer: Decimal = 0
        for _ in 0..<6 { odometer += 250; fills.append(fill(odometer, 10)) }
        for _ in 0..<5 { odometer += 300; fills.append(fill(odometer, 10)) }
        let measured = try #require(FuelEconomyCalculator.measured(fills, units: .us))
        #expect(measured.value == 30)
        #expect(measured.intervals == FuelEconomyCalculator.maxIntervals)
    }

    @Test func latestPriceComesFromMostRecentFillUp() throws {
        let latest = try #require(FuelEconomyCalculator.latestPrice([
            fill(1000, 10, cost: 35, day: 1),
            fill(1300, 10, cost: Decimal(string: "33.99")!, day: 5),
        ]))
        #expect(latest.price == Decimal(string: "3.399"))
    }

    @Test func effectiveProfilePrefersMeasuredValues() {
        let car = Vehicle(units: .us)
        car.fuelEconomy = 22
        car.fuelPrice = 4
        #expect(car.effectiveProfile.fuelEconomy == 22)

        for (odometer, cost) in [(Decimal(1000), Decimal(30)), (1300, 30)] {
            car.fillUps.append(FillUp(date: .now, odometer: odometer, volume: 10, totalCost: cost))
        }
        #expect(car.effectiveProfile.fuelEconomy == 30)
        #expect(car.effectiveProfile.fuelPrice == 3)
        // What the driver typed is kept as the fallback.
        #expect(car.profile.fuelEconomy == 22)
    }
}
