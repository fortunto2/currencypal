import Foundation
import SwiftData

/// Fetches exchange rates from Frankfurter API and caches in SwiftData
actor ExchangeRateService {
    private let baseURL = URL(string: "https://api.frankfurter.dev/v1/latest")!

    /// Fetch latest rates for a base currency from Frankfurter API
    func fetchRates(base: CurrencyCode) async throws -> FrankfurterResponse {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "base", value: base.rawValue)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        return try JSONDecoder().decode(FrankfurterResponse.self, from: data)
    }

    /// Update cached rates in SwiftData
    @MainActor
    func updateCache(base: CurrencyCode, context: ModelContext) async throws {
        let response = try await fetchRates(base: base)
        let now = Date()

        // Delete old rates for this base
        let baseName = base.rawValue
        try context.delete(model: ExchangeRate.self, where: #Predicate<ExchangeRate> {
            $0.baseCurrency == baseName
        })

        // Insert fresh rates
        for (currency, rate) in response.rates {
            let exchangeRate = ExchangeRate(
                baseCurrency: base.rawValue,
                targetCurrency: currency,
                rate: rate,
                fetchedAt: now
            )
            context.insert(exchangeRate)
        }

        // Self-rate (1:1)
        context.insert(ExchangeRate(
            baseCurrency: base.rawValue,
            targetCurrency: base.rawValue,
            rate: 1.0,
            fetchedAt: now
        ))

        try context.save()
    }
}

enum ExchangeRateError: LocalizedError {
    case networkError
    case noData

    var errorDescription: String? {
        switch self {
        case .networkError: "Unable to fetch exchange rates. Check your connection."
        case .noData: "No cached rates available."
        }
    }
}
