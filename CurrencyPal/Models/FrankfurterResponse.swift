import Foundation

/// API response from Frankfurter (frankfurter.dev)
/// Example: GET https://api.frankfurter.dev/v1/latest?base=USD
struct FrankfurterResponse: Codable {
    let base: String
    let date: String
    let rates: [String: Double]
}

/// Time-series API response from Frankfurter
/// Example: GET https://api.frankfurter.dev/v1/2026-01-09..2026-02-08?base=USD&symbols=EUR
struct FrankfurterTimeSeriesResponse: Codable {
    let base: String
    let startDate: String
    let endDate: String
    let rates: [String: [String: Double]]

    enum CodingKeys: String, CodingKey {
        case base
        case startDate = "start_date"
        case endDate = "end_date"
        case rates
    }
}
