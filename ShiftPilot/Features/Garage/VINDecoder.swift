import Foundation

struct DecodedVehicle: Equatable, Sendable {
    var year: Int?
    var make: String
    var model: String
    var trim: String
}

/// Looks up year, make and model from a VIN with NHTSA's free vPIC service.
/// Only the VIN is sent; no key or account is needed.
enum VINDecoder {
    enum DecodeError: LocalizedError {
        case invalidFormat
        case notFound
        case serviceUnavailable

        var errorDescription: String? {
            switch self {
            case .invalidFormat: "A VIN is 17 letters and numbers, without I, O or Q."
            case .notFound: "NHTSA couldn't find that VIN. Check it against your registration or the driver's door sticker."
            case .serviceUnavailable: "NHTSA's VIN service isn't responding right now. Try again in a minute, or enter the year, make and model yourself."
            }
        }
    }

    /// Uppercased with spaces and dashes removed.
    static func normalize(_ vin: String) -> String {
        vin.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    static func isWellFormed(_ vin: String) -> Bool {
        vin.count == 17 && vin.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) && !"IOQ".contains($0) }
    }

    /// The 9th-character check digit used on North American VINs. Other markets may not
    /// use it, so a mismatch is a warning, not an error.
    static func hasValidCheckDigit(_ vin: String) -> Bool {
        guard isWellFormed(vin) else { return false }
        let weights = [8, 7, 6, 5, 4, 3, 2, 10, 0, 9, 8, 7, 6, 5, 4, 3, 2]
        let sum = zip(vin, weights).reduce(0) { $0 + transliterate($1.0) * $1.1 }
        let remainder = sum % 11
        let expected: Character = remainder == 10 ? "X" : Character(String(remainder))
        return vin[vin.index(vin.startIndex, offsetBy: 8)] == expected
    }

    static func decode(_ rawVIN: String, session: URLSession = .shared) async throws -> DecodedVehicle {
        let vin = normalize(rawVIN)
        guard isWellFormed(vin) else { throw DecodeError.invalidFormat }
        let url = URL(string: "https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/\(vin)?format=json")!
        // NHTSA's servers occasionally return 503 for a moment; retry once before giving up.
        for attempt in 0..<2 {
            let (data, response) = try await session.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            if (200..<300).contains(status) {
                return try parse(data)
            }
            Log.persistence.error("VIN lookup returned HTTP \(status)")
            guard status >= 500, attempt == 0 else { break }
            try await Task.sleep(for: .seconds(1))
        }
        throw DecodeError.serviceUnavailable
    }

    static func parse(_ data: Data) throws -> DecodedVehicle {
        struct Response: Decodable {
            struct Result: Decodable {
                var ModelYear: String?
                var Make: String?
                var Model: String?
                var Trim: String?
            }
            var Results: [Result]
        }
        guard let result = (try? JSONDecoder().decode(Response.self, from: data))?.Results.first,
              let make = result.Make, !make.isEmpty else {
            throw DecodeError.notFound
        }
        return DecodedVehicle(
            year: result.ModelYear.flatMap(Int.init),
            make: tidy(make),
            model: result.Model ?? "",
            trim: result.Trim ?? ""
        )
    }

    /// NHTSA returns makes in capitals ("TOYOTA"); keep short ones like "BMW" as-is.
    private static func tidy(_ make: String) -> String {
        make.count > 3 && make == make.uppercased() ? make.capitalized : make
    }

    private static func transliterate(_ character: Character) -> Int {
        if let digit = character.wholeNumberValue { return digit }
        let values: [Character: Int] = [
            "A": 1, "B": 2, "C": 3, "D": 4, "E": 5, "F": 6, "G": 7, "H": 8,
            "J": 1, "K": 2, "L": 3, "M": 4, "N": 5, "P": 7, "R": 9,
            "S": 2, "T": 3, "U": 4, "V": 5, "W": 6, "X": 7, "Y": 8, "Z": 9,
        ]
        return values[character] ?? 0
    }
}
