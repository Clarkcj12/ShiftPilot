import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

/// Trimmed from a real api.eia.gov response (week of Oct 26, 2026).
private let fixture = Data("""
{"response":{"total":"5440","data":[
 {"period":"2026-10-26","duoarea":"NUS","area-name":"U.S.","product":"EPMR","value":"4.269","units":"$/GAL"},
 {"period":"2026-10-26","duoarea":"R1Y","area-name":"PADD 1B","product":"EPMR","value":"4.251","units":"$/GAL"},
 {"period":"2026-10-26","duoarea":"R10","area-name":"PADD 1","product":"EPMR","value":"4.022","units":"$/GAL"},
 {"period":"2026-10-19","duoarea":"NUS","area-name":"U.S.","product":"EPMR","value":"4.284","units":"$/GAL"}
]}}
""".utf8)

private func regional(_ price: String, area: String = "R1Y") -> RegionalFuelPrice {
    RegionalFuelPrice(pricePerGallon: Decimal(string: price)!, areaID: area, weekOf: .now, fetchedAt: .now, requestedArea: area)
}

struct FuelPriceAreaTests {
    @Test func marylandUsesCentralAtlanticThenEastCoastThenUS() {
        #expect(FuelPriceArea.candidates(forState: "MD") == ["R1Y", "R10", "NUS"])
        #expect(FuelPriceArea.candidates(forState: " maryland ") == ["R1Y", "R10", "NUS"])
    }

    @Test func statesWithTheirOwnSeriesTryItFirst() {
        #expect(FuelPriceArea.candidates(forState: "NY") == ["SNY", "R1Y", "R10", "NUS"])
        #expect(FuelPriceArea.candidates(forState: "TX") == ["STX", "R30", "NUS"])
        #expect(FuelPriceArea.candidates(forState: "CA") == ["SCA", "R50", "NUS"])
    }

    @Test func westCoastOutsideCaliforniaSkipsTheCaliforniaHeavyAverage() {
        #expect(FuelPriceArea.candidates(forState: "OR") == ["R5XCA", "R50", "NUS"])
    }

    @Test func unknownOrMissingStateUsesTheUSAverage() {
        #expect(FuelPriceArea.candidates(forState: nil) == ["NUS"])
        #expect(FuelPriceArea.candidates(forState: "ON") == ["NUS"])
        #expect(USState.code("Washington D.C.") == "DC")
    }

    @Test func onlyUSDollarDriversGetEIAPrices() {
        #expect(FuelPriceStore.isApplicable(state: "MD", currencyCode: "USD", region: .unitedStates))
        #expect(!FuelPriceStore.isApplicable(state: "MD", currencyCode: "CAD", region: .canada))
        #expect(!FuelPriceStore.isApplicable(state: "ON", currencyCode: "USD", region: .unitedStates))
        #expect(FuelPriceStore.isApplicable(state: "", currencyCode: "USD", region: .unitedStates))
        #expect(!FuelPriceStore.isApplicable(state: nil, currencyCode: "USD", region: .canada))
    }
}

struct EIAFuelPriceClientTests {
    @Test func parsesTheMostSpecificAreaAsDecimal() throws {
        let price = try #require(try EIAFuelPriceClient.parse(fixture, preferring: ["R1Y", "R10", "NUS"], fetchedAt: .now))
        #expect(price.pricePerGallon == Decimal(string: "4.251"))
        #expect(price.areaID == "R1Y")
        #expect(price.requestedArea == "R1Y")
        #expect(Calendar.current.component(.day, from: price.weekOf) == 26)
    }

    @Test func fallsBackWhenTheSpecificAreaHasNoRow() throws {
        let price = try #require(try EIAFuelPriceClient.parse(fixture, preferring: ["SNY", "R1Y", "R10", "NUS"], fetchedAt: .now))
        #expect(price.areaID == "R1Y")
        #expect(price.requestedArea == "SNY")
    }

    @Test func picksTheLatestWeekForAnArea() throws {
        let price = try #require(try EIAFuelPriceClient.parse(fixture, preferring: ["NUS"], fetchedAt: .now))
        #expect(price.pricePerGallon == Decimal(string: "4.269"))
    }

    @Test func noMatchingRowsIsNil() throws {
        #expect(try EIAFuelPriceClient.parse(fixture, preferring: ["R30"], fetchedAt: .now) == nil)
    }

    @Test func urlAsksForRegularInEachArea() {
        let query = EIAFuelPriceClient.url(areas: ["R1Y", "NUS"], apiKey: "k").query ?? ""
        #expect(query.contains("EPMR"))
        #expect(query.contains("R1Y"))
        #expect(query.contains("NUS"))
    }
}

@MainActor
struct FuelPricePrecedenceTests {
    private func car() throws -> (Vehicle, ModelContext) {
        let schema = Schema([Trip.self, TripPoint.self, Shift.self, Payout.self, TaxPayment.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let car = Vehicle(units: .us)
        context.insert(car)
        car.profile.fuelEconomy = 40
        return (car, context)
    }

    @Test func regionalFillsTheGapOnly() throws {
        let (car, context) = try car()
        #expect(car.fuelPriceSource(regional: nil) == .none)
        #expect(car.effectiveProfile(regional: regional("4.00")).fuelPrice == 4)

        car.profile.fuelPrice = Decimal(string: "3.50")
        #expect(car.effectiveProfile(regional: regional("4.00")).fuelPrice == Decimal(string: "3.50"))

        let fill = FillUp(date: .now, odometer: 1000, volume: 10, totalCost: 33)
        context.insert(fill)
        fill.vehicle = car
        #expect(car.effectiveProfile(regional: regional("4.00")).fuelPrice == Decimal(string: "3.3"))
    }

    @Test func metricConvertsGallonsToLiters() throws {
        let (car, _) = try car()
        car.profile.units = .metric
        let perLiter = try #require(car.effectiveProfile(regional: regional("3.785411784")).fuelPrice)
        #expect(abs(NSDecimalNumber(decimal: perLiter).doubleValue - 1) < 0.000001)
    }

    @Test func regionalPriceMakesNetProfitAvailable() throws {
        let (car, _) = try car()
        #expect(car.effectiveProfile(regional: nil).costPerMeter == nil)
        #expect(car.effectiveProfile(regional: regional("4.00")).costPerMeter != nil)
    }
}
