import Foundation
import SwiftData

enum GigPlatform: String, CaseIterable, Identifiable, Codable, Sendable {
    case doorDash, uber, uberEats, lyft, instacart, grubhub, shipt, spark, amazonFlex, other

    var id: Self { self }

    var name: String {
        switch self {
        case .doorDash: "DoorDash"
        case .uber: "Uber"
        case .uberEats: "Uber Eats"
        case .lyft: "Lyft"
        case .instacart: "Instacart"
        case .grubhub: "Grubhub"
        case .shipt: "Shipt"
        case .spark: "Spark"
        case .amazonFlex: "Amazon Flex"
        case .other: "Other"
        }
    }
}

/// A working session. Trips confirmed while a shift is active are attached to it.
@Model
final class Shift {
    var startedAt: Date
    var endedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Payout.shift)
    var payouts: [Payout] = []

    @Relationship(deleteRule: .nullify, inverse: \Trip.shift)
    var trips: [Trip] = []

    init(startedAt: Date) {
        self.startedAt = startedAt
    }

    var isActive: Bool { endedAt == nil }

    func snapshot(now: Date = .now) -> ShiftSnapshot {
        ShiftSnapshot(
            start: startedAt,
            end: endedAt ?? now,
            payouts: payouts.map { PayoutSnapshot(platform: $0.platform, amount: $0.amount, receivedAt: $0.receivedAt) },
            distanceMeters: trips.filter { $0.purpose != .personal }.reduce(0) { $0 + $1.distanceMeters }
        )
    }
}

/// Gross pay (including tips) from one platform.
@Model
final class Payout {
    var amount: Decimal
    var platformRawValue: String
    var receivedAt: Date
    var note: String
    var shift: Shift?

    init(amount: Decimal, platform: GigPlatform, receivedAt: Date, note: String = "") {
        self.amount = amount
        self.platformRawValue = platform.rawValue
        self.receivedAt = receivedAt
        self.note = note
    }

    var platform: GigPlatform { GigPlatform(rawValue: platformRawValue) ?? .other }
}
