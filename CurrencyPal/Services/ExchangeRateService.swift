import Foundation
import SwiftData

/// Fetches exchange rates from Frankfurter API and caches in SwiftData
actor ExchangeRateService {
    private let baseURL = URL(string: "https://api.frankfurter.dev/v1/latest")!
    private let timeSeriesBaseURL = "https://api.frankfurter.dev/v1/"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

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

    /// Fetch time-series rates for a currency pair
    func fetchTimeSeries(base: CurrencyCode, symbol: CurrencyCode, startDate: Date, endDate: Date) async throws -> FrankfurterTimeSeriesResponse {
        let start = Self.dateFormatter.string(from: startDate)
        let end = Self.dateFormatter.string(from: endDate)
        let urlString = "\(timeSeriesBaseURL)\(start)..\(end)?base=\(base.rawValue)&symbols=\(symbol.rawValue)"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.networkError
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        return try JSONDecoder().decode(FrankfurterTimeSeriesResponse.self, from: data)
    }

    /// Fetch 30-day historical data and cache it
    @MainActor
    func updateHistoricalCache(base: CurrencyCode, target: CurrencyCode, days: Int = 30, context: ModelContext) async throws {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!

        let response = try await fetchTimeSeries(base: base, symbol: target, startDate: startDate, endDate: endDate)

        // Delete old historical rates for this pair
        let baseName = base.rawValue
        let targetName = target.rawValue
        try context.delete(model: HistoricalRate.self, where: #Predicate<HistoricalRate> {
            $0.baseCurrency == baseName && $0.targetCurrency == targetName
        })

        // Insert new historical rates
        for (dateString, ratesDict) in response.rates {
            guard let rateValue = ratesDict[target.rawValue],
                  let date = Self.dateFormatter.date(from: dateString) else { continue }
            let historicalRate = HistoricalRate(
                baseCurrency: base.rawValue,
                targetCurrency: target.rawValue,
                rate: rateValue,
                date: date
            )
            context.insert(historicalRate)
        }

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
