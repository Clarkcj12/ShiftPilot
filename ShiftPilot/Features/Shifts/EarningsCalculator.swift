import Foundation

struct PayoutSnapshot: Sendable, Equatable {
    var platform: GigPlatform
    var amount: Decimal
    var receivedAt: Date
}

/// Plain-value view of a shift, so earnings math can be tested without SwiftData.
struct ShiftSnapshot: Sendable {
    var start: Date
    var end: Date
    var payouts: [PayoutSnapshot]
    var distanceMeters: Double
    /// Fuel and wear for the shift's business trips; nil until a vehicle is set up.
    var vehicleCost: Decimal? = nil

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var gross: Decimal { payouts.reduce(0) { $0 + $1.amount } }

    /// True EPH: gross pay over the whole shift, including waiting time between orders.
    var hourlyRate: Decimal? { EarningsCalculator.hourlyRate(gross, over: duration) }

    /// Gross minus fuel and wear.
    var netProfit: Decimal? { vehicleCost.map { gross - $0 } }

    /// Net profit over the whole shift.
    var netHourlyRate: Decimal? { netProfit.flatMap { EarningsCalculator.hourlyRate($0, over: duration) } }

    func earningsPerDistance(in unit: DistanceUnit) -> Decimal? {
        let distance = unit.value(fromMeters: distanceMeters)
        guard distance >= 0.1 else { return nil }
        return gross / Decimal(distance)
    }
}

struct EarningsBreakdown<Key: Hashable & Sendable>: Identifiable, Sendable {
    var key: Key
    var gross: Decimal
    var seconds: TimeInterval

    var id: Key { key }
    var hourlyRate: Decimal? { EarningsCalculator.hourlyRate(gross, over: seconds) }
}

enum Daypart: Int, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, afternoon, dinner, lateNight

    init(hour: Int) {
        self = switch hour {
        case 5..<10: .breakfast
        case 10..<14: .lunch
        case 14..<17: .afternoon
        case 17..<21: .dinner
        default: .lateNight
        }
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .afternoon: "Afternoon"
        case .dinner: "Dinner"
        case .lateNight: "Late night"
        }
    }

    var hours: String {
        switch self {
        case .breakfast: "5–10 AM"
        case .lunch: "10 AM–2 PM"
        case .afternoon: "2–5 PM"
        case .dinner: "5–9 PM"
        case .lateNight: "9 PM–5 AM"
        }
    }
}

enum EarningsCalculator {
    /// Rates over shorter spans are too noisy to show.
    static let minimumDuration: TimeInterval = 60

    static func hourlyRate(_ gross: Decimal, over seconds: TimeInterval) -> Decimal? {
        guard seconds >= minimumDuration else { return nil }
        return gross / Decimal(seconds / 3600)
    }

    /// Earnings per platform, best EPH first.
    ///
    /// When multi-apping, a shift's full duration counts toward every platform that
    /// paid during it, so each app's EPH reflects what that shift was worth to it.
    static func byPlatform(_ shifts: [ShiftSnapshot]) -> [EarningsBreakdown<GigPlatform>] {
        var gross: [GigPlatform: Decimal] = [:]
        var seconds: [GigPlatform: TimeInterval] = [:]
        for shift in shifts {
            for payout in shift.payouts {
                gross[payout.platform, default: 0] += payout.amount
            }
            for platform in Set(shift.payouts.map(\.platform)) {
                seconds[platform, default: 0] += shift.duration
            }
        }
        return gross
            .map { EarningsBreakdown(key: $0.key, gross: $0.value, seconds: seconds[$0.key] ?? 0) }
            .sorted { ($0.hourlyRate ?? -1) > ($1.hourlyRate ?? -1) }
    }

    /// Earnings per time of day. Shift time is split across dayparts; pay is bucketed
    /// by when each payout was received.
    static func byDaypart(_ shifts: [ShiftSnapshot], calendar: Calendar = .current) -> [EarningsBreakdown<Daypart>] {
        var gross: [Daypart: Decimal] = [:]
        var seconds: [Daypart: TimeInterval] = [:]
        for shift in shifts {
            for (hour, duration) in secondsByHourOfDay(from: shift.start, to: shift.end, calendar: calendar) {
                seconds[Daypart(hour: hour), default: 0] += duration
            }
            for payout in shift.payouts {
                gross[Daypart(hour: calendar.component(.hour, from: payout.receivedAt)), default: 0] += payout.amount
            }
        }
        return Daypart.allCases.compactMap { daypart in
            guard seconds[daypart] != nil || gross[daypart] != nil else { return nil }
            return EarningsBreakdown(key: daypart, gross: gross[daypart] ?? 0, seconds: seconds[daypart] ?? 0)
        }
    }

    /// How many seconds of `start..<end` fall in each clock hour (0–23).
    static func secondsByHourOfDay(from start: Date, to end: Date, calendar: Calendar) -> [Int: TimeInterval] {
        var result: [Int: TimeInterval] = [:]
        var cursor = start
        while cursor < end {
            let hour = calendar.component(.hour, from: cursor)
            let nextHour = calendar.nextDate(after: cursor, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? end
            let chunkEnd = min(nextHour, end)
            result[hour, default: 0] += chunkEnd.timeIntervalSince(cursor)
            cursor = chunkEnd
        }
        return result
    }
}
