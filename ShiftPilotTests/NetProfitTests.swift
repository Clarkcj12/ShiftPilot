import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

struct VehicleProfileTests {
    @Test func usCostPerMile() throws {
        // 25 MPG at $3.50/gal = 14¢/mi fuel, plus 10¢/mi wear.
        let profile = VehicleProfile(units: .us, fuelEconomy: 25, fuelPrice: Decimal(string: "3.50"), wearPerDistance: Decimal(string: "0.10"))
        let perMile = try #require(profile.costPerDistance)
        #expect(TaxCalculator.round(perMile) == Decimal(string: "0.24"))
    }

    @Test func metricCostPerKilometer() throws {
        // 8 L/100 km at €1.80/L = 14.4¢/km.
        let profile = VehicleProfile(units: .metric, fuelEconomy: 8, fuelPrice: Decimal(string: "1.80"))
        let perKm = try #require(profile.costPerDistance)
        #expect(TaxCalculator.round(perKm * 10) == Decimal(string: "1.44"))
    }

    @Test func notConfiguredWithoutEconomyAndPrice() {
        #expect(VehicleProfile(units: .us).costPerMeter == nil)
        #expect(VehicleProfile(units: .us, fuelEconomy: 25).costPerMeter == nil)
        #expect(VehicleProfile(units: .us, fuelEconomy: 0, fuelPrice: 3).costPerMeter == nil)
    }
}

@MainActor
struct NetProfitTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Trip.self, TripPoint.self, Shift.self, Payout.self, Vehicle.self, OdometerReading.self, FillUp.self, Expense.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    @Test func recorderCapturesVehicleAndCostOnEachTrip() throws {
        let context = try makeContext()
        let garage = GarageStore(context: context, defaults: UserDefaults(suiteName: #function)!)
        let car = garage.addVehicle(units: .metric)
        car.profile = VehicleProfile(units: .metric, fuelEconomy: 10, fuelPrice: 10)  // $0.001/m
        let recorder = TripRecorder(context: context, currentVehicle: { garage.current })

        recorder.begin(trigger: .manual, at: .now)
        recorder.confirm()
        recorder.finish(at: .now)
        car.fuelPrice = nil
        recorder.begin(trigger: .manual, at: .now.addingTimeInterval(1))
        recorder.confirm()
        recorder.finish(at: .now)

        let trips = try context.fetch(FetchDescriptor<Trip>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(trips.map(\.vehicleCostPerMeter) == [Decimal(string: "0.001"), nil])
        #expect(trips.allSatisfy { $0.vehicle == car })
    }

    @Test func shiftNetProfitUsesTripCostThenFallback() throws {
        let context = try makeContext()
        let shifts = ShiftManager(context: context)
        shifts.startShift(at: .now.addingTimeInterval(-7200))
        let shift = try #require(shifts.activeShift)
        shifts.addPayout(50, platform: .doorDash, receivedAt: .now, to: shift)

        let captured = Trip(startedAt: .now, trigger: .carPlay)
        captured.distanceMeters = 10_000
        captured.vehicleCostPerMeter = Decimal(string: "0.0002")  // $2.00
        let older = Trip(startedAt: .now, trigger: .carPlay)
        older.distanceMeters = 5_000
        let errand = Trip(startedAt: .now, trigger: .carPlay)
        errand.distanceMeters = 50_000
        errand.vehicleCostPerMeter = 1
        for trip in [captured, older, errand] {
            context.insert(trip)
            trip.shift = shift
            trip.purpose = .business
        }
        errand.purpose = .personal

        // One trip has no captured cost and there's no vehicle: net is unknown.
        #expect(shift.snapshot().netProfit == nil)

        // The older trip falls back to the current cost: 5 km × $0.0001 = $0.50.
        let snapshot = shift.snapshot(costPerMeter: Decimal(string: "0.0001"))
        #expect(snapshot.vehicleCost == Decimal(string: "2.5"))
        #expect(snapshot.netProfit == Decimal(string: "47.5"))
        #expect(snapshot.netHourlyRate.map(TaxCalculator.round) == Decimal(string: "23.75"))
    }
}
