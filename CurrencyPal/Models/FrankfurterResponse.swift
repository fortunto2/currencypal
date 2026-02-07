import Foundation

/// API response from Frankfurter (frankfurter.dev)
/// Example: GET https://api.frankfurter.dev/v1/latest?base=USD
struct FrankfurterResponse: Codable {
    let base: String
    let date: String
    let rates: [String: Double]
}
