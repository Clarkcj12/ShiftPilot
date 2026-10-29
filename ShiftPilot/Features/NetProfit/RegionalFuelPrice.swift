import Foundation
import Observation

/// The U.S. EIA weekly average retail price for regular gasoline in the driver's area.
/// Used only when the driver hasn't entered a price or logged a fill-up.
struct RegionalFuelPrice: Codable, Sendable, Equatable {
    /// Dollars per gallon.
    var pricePerGallon: Decimal
    /// EIA `duoarea` code, e.g. "R1Y".
    var areaID: String
    /// The week the average covers (EIA's `period` is the Monday it starts).
    var weekOf: Date
    var fetchedAt: Date
    /// The most specific area that was asked for, so a change of state refetches.
    var requestedArea: String

    var areaName: String { FuelPriceArea.name(of: areaID) }

    /// Price per the profile's volume unit.
    func price(per units: VehicleProfile.Units) -> Decimal {
        switch units {
        case .us: pricePerGallon
        case .metric: pricePerGallon / Decimal(string: "3.785411784")!
        }
    }
}

/// EIA price areas, most specific first. Definitions: EIA petroleum PADD notes
/// (eia.gov/dnav/pet/TblDefs/pet_pri_resid_tbldef2.asp).
enum FuelPriceArea {
    static let unitedStates = "NUS"

    /// States with their own weekly EIA series.
    private static let stateSeries: [String: String] = [
        "CA": "SCA", "CO": "SCO", "FL": "SFL", "MA": "SMA", "MN": "SMN",
        "NY": "SNY", "OH": "SOH", "TX": "STX", "WA": "SWA",
    ]

    private static let padds: [(areaID: String, parent: String?, states: Set<String>)] = [
        ("R1X", "R10", ["CT", "ME", "MA", "NH", "RI", "VT"]),
        ("R1Y", "R10", ["DE", "DC", "MD", "NJ", "NY", "PA"]),
        ("R1Z", "R10", ["FL", "GA", "NC", "SC", "VA", "WV"]),
        ("R20", nil, ["IL", "IN", "IA", "KS", "KY", "MI", "MN", "MO", "NE", "ND", "OH", "OK", "SD", "TN", "WI"]),
        ("R30", nil, ["AL", "AR", "LA", "MS", "NM", "TX"]),
        ("R40", nil, ["CO", "ID", "MT", "UT", "WY"]),
        // California dominates the PADD 5 average, so other West Coast states use "PADD 5 except California".
        ("R5XCA", "R50", ["AK", "AZ", "HI", "NV", "OR", "WA"]),
        ("R50", nil, ["CA"]),
    ]

    private static let names: [String: String] = [
        "NUS": "U.S.", "R10": "East Coast", "R1X": "New England", "R1Y": "Central Atlantic",
        "R1Z": "Lower Atlantic", "R20": "Midwest", "R30": "Gulf Coast", "R40": "Rocky Mountain",
        "R50": "West Coast", "R5XCA": "West Coast (except California)",
        "SCA": "California", "SCO": "Colorado", "SFL": "Florida", "SMA": "Massachusetts",
        "SMN": "Minnesota", "SNY": "New York", "SOH": "Ohio", "STX": "Texas", "SWA": "Washington",
    ]

    static func name(of areaID: String) -> String { names[areaID] ?? areaID }

    /// Areas to try for a state, most specific first, always ending with the U.S. average.
    static func candidates(forState state: String?) -> [String] {
        guard let state = state.flatMap(USState.code) else { return [unitedStates] }
        var areas: [String] = []
        if let series = stateSeries[state] { areas.append(series) }
        if let padd = padds.first(where: { $0.states.contains(state) }) {
            areas.append(padd.areaID)
            if let parent = padd.parent { areas.append(parent) }
        }
        areas.append(unitedStates)
        return areas
    }
}

enum USState {
    private static let byName: [String: String] = [
        "ALABAMA": "AL", "ALASKA": "AK", "ARIZONA": "AZ", "ARKANSAS": "AR", "CALIFORNIA": "CA",
        "COLORADO": "CO", "CONNECTICUT": "CT", "DELAWARE": "DE", "DISTRICT OF COLUMBIA": "DC",
        "FLORIDA": "FL", "GEORGIA": "GA", "HAWAII": "HI", "IDAHO": "ID", "ILLINOIS": "IL",
        "INDIANA": "IN", "IOWA": "IA", "KANSAS": "KS", "KENTUCKY": "KY", "LOUISIANA": "LA",
        "MAINE": "ME", "MARYLAND": "MD", "MASSACHUSETTS": "MA", "MICHIGAN": "MI", "MINNESOTA": "MN",
        "MISSISSIPPI": "MS", "MISSOURI": "MO", "MONTANA": "MT", "NEBRASKA": "NE", "NEVADA": "NV",
        "NEW HAMPSHIRE": "NH", "NEW JERSEY": "NJ", "NEW MEXICO": "NM", "NEW YORK": "NY",
        "NORTH CAROLINA": "NC", "NORTH DAKOTA": "ND", "OHIO": "OH", "OKLAHOMA": "OK", "OREGON": "OR",
        "PENNSYLVANIA": "PA", "RHODE ISLAND": "RI", "SOUTH CAROLINA": "SC", "SOUTH DAKOTA": "SD",
        "TENNESSEE": "TN", "TEXAS": "TX", "UTAH": "UT", "VERMONT": "VT", "VIRGINIA": "VA",
        "WASHINGTON": "WA", "WEST VIRGINIA": "WV", "WISCONSIN": "WI", "WYOMING": "WY",
    ]
    private static let codes = Set(byName.values)

    /// Two-letter code for "md", " MD ", "Maryland" or "Washington DC"; nil if not a U.S. state.
    static func code(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            .replacingOccurrences(of: ".", with: "")
        if codes.contains(key) { return key }
        if key == "WASHINGTON DC" || key == "DC" { return "DC" }
        return byName[key]
    }
}

/// EIA Open Data API v2 (api.eia.gov), weekly retail gasoline prices.
enum EIAFuelPriceClient {
    enum Failure: Error { case badStatus(Int), noData }

    static func url(areas: [String], apiKey: String) -> URL {
        var components = URLComponents(string: "https://api.eia.gov/v2/petroleum/pri/gnd/data/")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "frequency", value: "weekly"),
            URLQueryItem(name: "data[0]", value: "value"),
            URLQueryItem(name: "facets[product][]", value: "EPMR"),
            URLQueryItem(name: "sort[0][column]", value: "period"),
            URLQueryItem(name: "sort[0][direction]", value: "desc"),
            URLQueryItem(name: "length", value: String(areas.count * 3)),
        ] + areas.map { URLQueryItem(name: "facets[duoarea][]", value: $0) }
        return components.url!
    }

    static func fetch(areas: [String], apiKey: String, session: URLSession = .shared, now: Date = .now) async throws -> RegionalFuelPrice {
        let (data, response) = try await session.data(from: url(areas: areas, apiKey: apiKey))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.badStatus(http.statusCode)
        }
        guard let price = try parse(data, preferring: areas, fetchedAt: now) else { throw Failure.noData }
        return price
    }

    /// The latest row of the most specific area that has one.
    static func parse(_ data: Data, preferring areas: [String], fetchedAt: Date) throws -> RegionalFuelPrice? {
        struct Envelope: Decodable {
            struct Response: Decodable { var data: [Row] }
            struct Row: Decodable {
                var period: String
                var duoarea: String
                var value: String?
            }
            var response: Response
        }
        let rows = try JSONDecoder().decode(Envelope.self, from: data).response.data
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        formatter.dateFormat = "yyyy-MM-dd"

        for area in areas {
            let latest = rows
                .filter { $0.duoarea == area }
                .compactMap { row -> (Date, Decimal)? in
                    guard let date = formatter.date(from: row.period),
                          let value = row.value.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }),
                          value > 0 else { return nil }
                    return (date, value)
                }
                .max { $0.0 < $1.0 }
            if let (date, value) = latest {
                return RegionalFuelPrice(pricePerGallon: value, areaID: area, weekOf: date, fetchedAt: fetchedAt, requestedArea: areas.first ?? area)
            }
        }
        return nil
    }
}

/// Fetches and caches the regional price. Refreshes at most once a day, keeps the last
/// good value on failure, and never blocks the UI.
@MainActor
@Observable
final class FuelPriceStore {
    static let cacheKey = "regionalFuelPrice"
    private static let refreshInterval: TimeInterval = 24 * 60 * 60

    private(set) var latest: RegionalFuelPrice?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let apiKey: String?
    @ObservationIgnored private var isFetching = false

    init(defaults: UserDefaults = .standard, apiKey: String? = FuelPriceStore.bundledAPIKey) {
        self.defaults = defaults
        self.apiKey = apiKey
        latest = defaults.data(forKey: Self.cacheKey).flatMap { try? JSONDecoder().decode(RegionalFuelPrice.self, from: $0) }
    }

    /// From `EIA_API_KEY` in Secrets.xcconfig. Debug builds fall back to EIA's rate-limited demo key.
    nonisolated static var bundledAPIKey: String? {
        let key = (Bundle.main.object(forInfoDictionaryKey: "EIAAPIKey") as? String)?
            .trimmingCharacters(in: .whitespaces)
        if let key, !key.isEmpty { return key }
        #if DEBUG
        return "DEMO_KEY"
        #else
        return nil
        #endif
    }

    /// EIA prices are U.S. dollars, so only U.S. drivers paying in dollars get them.
    nonisolated static func isApplicable(state: String?, currencyCode: String = Format.currencyCode, region: Locale.Region? = Locale.current.region) -> Bool {
        guard currencyCode == "USD" else { return false }
        if let state, !state.trimmingCharacters(in: .whitespaces).isEmpty {
            return USState.code(state) != nil
        }
        return region == .unitedStates
    }

    /// The cached price if it covers this vehicle's state.
    func price(forState state: String?) -> RegionalFuelPrice? {
        guard Self.isApplicable(state: state), let latest,
              latest.requestedArea == FuelPriceArea.candidates(forState: state).first else { return nil }
        return latest
    }

    func refreshIfNeeded(state: String?, now: Date = .now) async {
        guard let apiKey, !isFetching, Self.isApplicable(state: state) else { return }
        let areas = FuelPriceArea.candidates(forState: state)
        if let latest, latest.requestedArea == areas.first, now.timeIntervalSince(latest.fetchedAt) < Self.refreshInterval {
            return
        }
        isFetching = true
        defer { isFetching = false }
        do {
            let price = try await EIAFuelPriceClient.fetch(areas: areas, apiKey: apiKey, now: now)
            latest = price
            if let data = try? JSONEncoder().encode(price) {
                defaults.set(data, forKey: Self.cacheKey)
            }
            Log.persistence.info("Regional fuel price \(price.pricePerGallon) (\(price.areaID))")
        } catch {
            Log.persistence.error("Regional fuel price fetch failed: \(error.localizedDescription)")
        }
    }
}
