import Foundation
import SwiftData
import Testing
@testable import ShiftPilot

struct VINDecoderTests {
    @Test func validatesFormatAndCheckDigit() {
        #expect(VINDecoder.normalize(" 1hgcm8-2633a004352 ") == "1HGCM82633A004352")
        #expect(VINDecoder.isWellFormed("1HGCM82633A004352"))
        #expect(!VINDecoder.isWellFormed("1HGCM82633A00435"))   // 16 characters
        #expect(!VINDecoder.isWellFormed("1HGCM82633A00435O"))  // O isn't allowed
        #expect(VINDecoder.hasValidCheckDigit("1HGCM82633A004352"))
        #expect(!VINDecoder.hasValidCheckDigit("1HGCM82643A004352"))
    }

    @Test func parsesNHTSAResponse() throws {
        let json = #"{"Results":[{"ModelYear":"2003","Make":"HONDA","Model":"Accord","Trim":"EX-V6"}]}"#
        let decoded = try VINDecoder.parse(Data(json.utf8))
        #expect(decoded == DecodedVehicle(year: 2003, make: "Honda", model: "Accord", trim: "EX-V6"))

        let bmw = try VINDecoder.parse(Data(#"{"Results":[{"ModelYear":"2020","Make":"BMW","Model":"X3"}]}"#.utf8))
        #expect(bmw.make == "BMW")

        #expect(throws: VINDecoder.DecodeError.self) {
            try VINDecoder.parse(Data(#"{"Results":[{"Make":""}]}"#.utf8))
        }
    }
}

@MainActor
struct GarageStoreTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Trip.self, TripPoint.self, Shift.self, Payout.self, Vehicle.self, OdometerReading.self, FillUp.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func migratesLegacyProfileIntoFirstVehicle() throws {
        let context = try makeContext()
        let defaults = freshDefaults(#function)
        let legacy = VehicleProfile(units: .us, fuelEconomy: 25, fuelPrice: Decimal(string: "3.5"))
        defaults.set(try JSONEncoder().encode(legacy), forKey: GarageStore.legacyProfileKey)

        let garage = GarageStore(context: context, defaults: defaults)
        #expect(garage.current?.profile == legacy)
        #expect(defaults.data(forKey: GarageStore.legacyProfileKey) == nil)
    }

    @Test func firstVehicleIsCurrentAndDeletingPromotesNext() throws {
        let context = try makeContext()
        let garage = GarageStore(context: context, defaults: freshDefaults(#function))
        let first = garage.addVehicle(units: .us)
        let second = garage.addVehicle(units: .us)
        #expect(garage.current == first)

        garage.makeCurrent(second)
        #expect(garage.current == second)
        #expect(!first.isCurrent)

        garage.delete(second)
        #expect(garage.current == first)
    }

    @Test func odometerDistanceForYear() throws {
        let context = try makeContext()
        let garage = GarageStore(context: context, defaults: freshDefaults(#function))
        let car = garage.addVehicle(units: .us)
        let calendar = Calendar.current
        let jan = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let dec = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!

        garage.addReading(40_000, on: jan, to: car)
        #expect(car.odometerDistance(in: 2026, calendar: calendar) == nil)
        garage.addReading(52_500, on: dec, to: car)
        #expect(car.odometerDistance(in: 2026, calendar: calendar) == 12_500)
    }

    @Test func remindersFlagExpiringPapers() throws {
        let context = try makeContext()
        let car = Vehicle(units: .us)
        context.insert(car)
        let now = Date.now
        car.insuranceExpires = Calendar.current.date(byAdding: .day, value: 10, to: now)
        car.registrationExpires = Calendar.current.date(byAdding: .day, value: -1, to: now)

        let reminders = VehicleReminder.upcoming(for: car, now: now)
        #expect(reminders.map(\.title) == ["Insurance expires in 10 days", "Registration expired"])
        #expect(reminders.map(\.isOverdue) == [false, true])
    }
}
