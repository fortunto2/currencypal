import Foundation
import SwiftData

/// Fetches exchange rates from Frankfurter API (fiat) and CoinGecko (crypto), caches in SwiftData
actor ExchangeRateService {
    private let frankfurterBaseURL = URL(string: "https://api.frankfurter.dev/v1/latest")!
    private let timeSeriesBaseURL = "https://api.frankfurter.dev/v1/"
    private let coinGeckoBaseURL = "https://api.coingecko.com/api/v3"

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Frankfurter (Fiat)

    /// Fetch latest fiat rates from Frankfurter API
    func fetchRates(base: CurrencyCode) async throws -> FrankfurterResponse {
        var components = URLComponents(url: frankfurterBaseURL, resolvingAgainstBaseURL: false)!
        let baseCode = base.isCrypto ? CurrencyCode.USD : base
        components.queryItems = [URLQueryItem(name: "base", value: baseCode.rawValue)]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        return try JSONDecoder().decode(FrankfurterResponse.self, from: data)
    }

    // MARK: - CoinGecko (Crypto)

    /// Fetch crypto prices in a given fiat currency from CoinGecko
    func fetchCryptoPrices(vsCurrency: String = "usd") async throws -> [String: Double] {
        let ids = CurrencyCode.cryptoCases.compactMap(\.coinGeckoId).joined(separator: ",")
        let urlString = "\(coinGeckoBaseURL)/simple/price?ids=\(ids)&vs_currencies=\(vsCurrency.lowercased())"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.networkError
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        // Response: {"bitcoin":{"usd":97000},"ethereum":{"usd":3200},...}
        let json = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        var prices: [String: Double] = [:]
        for crypto in CurrencyCode.cryptoCases {
            if let geckoId = crypto.coinGeckoId,
               let price = json[geckoId]?[vsCurrency.lowercased()] {
                prices[crypto.rawValue] = price
            }
        }
        return prices
    }

    // MARK: - Supplementary Fiat (RUB etc.)

    /// Fetch rates from open.er-api.com for currencies not in ECB (e.g. RUB)
    func fetchSupplementaryRates(base: String = "USD") async throws -> [String: Double] {
        let urlString = "https://open.er-api.com/v6/latest/\(base)"
        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.networkError
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        // Response: {"result":"success","base_code":"USD","rates":{"RUB":96.5,...}}
        let json = try JSONDecoder().decode(OpenERResponse.self, from: data)
        return json.rates
    }

    // MARK: - Combined Cache Update

    /// Update cached rates: fiat from Frankfurter + crypto from CoinGecko
    @MainActor
    func updateCache(base: CurrencyCode, context: ModelContext) async throws {
        let now = Date()
        let baseName = base.rawValue

        // Delete old rates for this base
        try context.delete(model: ExchangeRate.self, where: #Predicate<ExchangeRate> {
            $0.baseCurrency == baseName
        })

        // 1) Fiat rates from Frankfurter (always relative to a fiat base)
        //    If base is crypto or supplementary fiat (RUB), use USD as pivot
        let fiatBase = (base.isCrypto || base.isSupplementaryFiat) ? CurrencyCode.USD : base
        let fiatResponse = try await fetchRates(base: fiatBase)

        // 2) Crypto prices in USD from CoinGecko
        let cryptoPricesInUSD = try? await fetchCryptoPrices(vsCurrency: "usd")

        // Get the USD rate relative to fiatBase (for cross-calculation)
        let usdRateFromBase: Double
        if fiatBase == .USD {
            usdRateFromBase = 1.0
        } else {
            usdRateFromBase = fiatResponse.rates["USD"] ?? 1.0
        }

        // If base is crypto, we need its USD price
        var basePriceInUSD: Double = 1.0
        if base.isCrypto {
            guard let prices = cryptoPricesInUSD,
                  let price = prices[base.rawValue], price > 0 else {
                throw ExchangeRateError.networkError
            }
            basePriceInUSD = price
        }

        // If base is supplementary fiat (RUB), get its USD rate
        // open.er-api returns: 1 USD = X RUB, so 1 RUB = 1/X USD
        var baseSupplementaryUSDRate: Double = 1.0
        if base.isSupplementaryFiat {
            let suppRates = try await fetchSupplementaryRates(base: "USD")
            if let rubPerUSD = suppRates[base.rawValue], rubPerUSD > 0 {
                baseSupplementaryUSDRate = rubPerUSD
                // usdRateFromBase for supplementary: 1 RUB = 1/rubPerUSD USD
                // But we use USD-based Frankfurter, so to convert:
                // 1 RUB in target = (1/rubPerUSD) * frankfurterRate[target]
            }
        }

        // Insert fiat rates (from Frankfurter, USD-based when base is crypto/supplementary)
        for (currency, rate) in fiatResponse.rates {
            let adjustedRate: Double
            if base.isCrypto {
                adjustedRate = basePriceInUSD * rate
            } else if base.isSupplementaryFiat {
                // fiatResponse is USD-based: rate = how many `currency` per 1 USD
                // We need: how many `currency` per 1 base (e.g. RUB)
                // 1 RUB = (1/baseSupplementaryUSDRate) USD
                // 1 RUB = (1/baseSupplementaryUSDRate) * rate `currency`
                adjustedRate = rate / baseSupplementaryUSDRate
            } else {
                adjustedRate = rate
            }
            context.insert(ExchangeRate(
                baseCurrency: baseName,
                targetCurrency: currency,
                rate: adjustedRate,
                fetchedAt: now
            ))
        }

        // Insert crypto rates (crypto as targets)
        if let prices = cryptoPricesInUSD {
            for (cryptoCode, priceInUSD) in prices {
                guard priceInUSD > 0 else { continue }
                let rate: Double
                if base.isCrypto {
                    rate = basePriceInUSD / priceInUSD
                } else if base.isSupplementaryFiat {
                    // 1 RUB = (1/baseSupplementaryUSDRate) USD = (1/baseSupplementaryUSDRate)/priceInUSD crypto
                    rate = 1.0 / (baseSupplementaryUSDRate * priceInUSD)
                } else {
                    // 1 base = usdRateFromBase USD = usdRateFromBase/priceInUSD crypto
                    rate = usdRateFromBase / priceInUSD
                }
                context.insert(ExchangeRate(
                    baseCurrency: baseName,
                    targetCurrency: cryptoCode,
                    rate: rate,
                    fetchedAt: now
                ))
            }
        }

        // 3) Supplementary fiat rates (RUB etc.) from open.er-api.com
        let supplementaryCodes = CurrencyCode.allCases.filter(\.isSupplementaryFiat)
        if !supplementaryCodes.isEmpty {
            if let suppRates = try? await fetchSupplementaryRates(base: "USD") {
                for code in supplementaryCodes {
                    guard let rateInUSD = suppRates[code.rawValue], rateInUSD > 0 else { continue }
                    let rate: Double
                    if base.isCrypto {
                        // 1 crypto = basePriceInUSD USD = basePriceInUSD * rateInUSD RUB
                        rate = basePriceInUSD * rateInUSD
                    } else if base == .USD {
                        rate = rateInUSD
                    } else if code == base {
                        rate = 1.0
                    } else {
                        // 1 base = usdRateFromBase USD = usdRateFromBase * rateInUSD supplementary
                        rate = usdRateFromBase * rateInUSD
                    }
                    context.insert(ExchangeRate(
                        baseCurrency: baseName,
                        targetCurrency: code.rawValue,
                        rate: rate,
                        fetchedAt: now
                    ))
                }
            }

            // If base IS a supplementary currency, also insert fiat targets
            if base.isSupplementaryFiat {
                if let suppRates = try? await fetchSupplementaryRates(base: base.rawValue) {
                    for fiat in CurrencyCode.fiatCases where !fiat.isSupplementaryFiat && fiat != base {
                        if let rate = suppRates[fiat.rawValue], rate > 0 {
                            context.insert(ExchangeRate(
                                baseCurrency: baseName,
                                targetCurrency: fiat.rawValue,
                                rate: rate,
                                fetchedAt: now
                            ))
                        }
                    }
                }
            }
        }

        // Self-rate (1:1)
        context.insert(ExchangeRate(
            baseCurrency: baseName,
            targetCurrency: baseName,
            rate: 1.0,
            fetchedAt: now
        ))

        try context.save()
    }

    // MARK: - Time Series (Fiat only)

    /// Fetch time-series rates for a fiat currency pair
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

    /// Fetch CoinGecko 30-day market chart for a crypto
    func fetchCryptoHistory(coinId: String, days: Int = 30) async throws -> [(date: Date, rate: Double)] {
        let urlString = "\(coinGeckoBaseURL)/coins/\(coinId)/market_chart?vs_currency=usd&days=\(days)&interval=daily"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.networkError
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ExchangeRateError.networkError
        }

        // Response: {"prices":[[timestamp_ms, price], ...], ...}
        let json = try JSONDecoder().decode(CoinGeckoMarketChart.self, from: data)
        return json.prices.map { pair in
            (date: Date(timeIntervalSince1970: pair[0] / 1000), rate: pair[1])
        }
    }

    /// Fetch 30-day historical data and cache it
    @MainActor
    func updateHistoricalCache(base: CurrencyCode, target: CurrencyCode, days: Int = 30, context: ModelContext) async throws {
        let baseName = base.rawValue
        let targetName = target.rawValue

        // Delete old historical rates for this pair
        try context.delete(model: HistoricalRate.self, where: #Predicate<HistoricalRate> {
            $0.baseCurrency == baseName && $0.targetCurrency == targetName
        })

        if !base.isCrypto && !target.isCrypto {
            // Fiat-to-fiat: use Frankfurter time series
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
            let response = try await fetchTimeSeries(base: base, symbol: target, startDate: startDate, endDate: endDate)

            for (dateString, ratesDict) in response.rates {
                guard let rateValue = ratesDict[target.rawValue],
                      let date = Self.dateFormatter.date(from: dateString) else { continue }
                context.insert(HistoricalRate(
                    baseCurrency: baseName, targetCurrency: targetName,
                    rate: rateValue, date: date
                ))
            }
        } else if !base.isCrypto && target.isCrypto {
            // Fiat-to-crypto: get crypto USD history, convert via fiat
            guard let geckoId = target.coinGeckoId else { throw ExchangeRateError.noData }
            let history = try await fetchCryptoHistory(coinId: geckoId, days: days)
            // Get fiat base -> USD rate (current, for simplicity)
            let fiatResponse = try await fetchRates(base: base)
            let usdRate = fiatResponse.rates["USD"] ?? 1.0

            for point in history {
                guard point.rate > 0 else { continue }
                // 1 base = usdRate USD = usdRate/cryptoPrice crypto
                let rate = usdRate / point.rate
                context.insert(HistoricalRate(
                    baseCurrency: baseName, targetCurrency: targetName,
                    rate: rate, date: point.date
                ))
            }
        } else if base.isCrypto && !target.isCrypto {
            // Crypto-to-fiat: get crypto USD history, convert to target fiat
            guard let geckoId = base.coinGeckoId else { throw ExchangeRateError.noData }
            let history = try await fetchCryptoHistory(coinId: geckoId, days: days)
            // Get USD -> target fiat rate
            let fiatResponse = try await fetchRates(base: .USD)
            let targetFiatRate = fiatResponse.rates[target.rawValue] ?? 1.0

            for point in history {
                // 1 crypto = cryptoPrice USD = cryptoPrice * targetFiatRate target
                let rate = point.rate * targetFiatRate
                context.insert(HistoricalRate(
                    baseCurrency: baseName, targetCurrency: targetName,
                    rate: rate, date: point.date
                ))
            }
        } else {
            // Crypto-to-crypto: get both histories in USD
            guard let baseId = base.coinGeckoId, let targetId = target.coinGeckoId else {
                throw ExchangeRateError.noData
            }
            let baseHistory = try await fetchCryptoHistory(coinId: baseId, days: days)
            let targetHistory = try await fetchCryptoHistory(coinId: targetId, days: days)

            // Match by closest date
            for basePoint in baseHistory {
                guard basePoint.rate > 0 else { continue }
                if let targetPoint = targetHistory.min(by: {
                    abs($0.date.timeIntervalSince(basePoint.date)) < abs($1.date.timeIntervalSince(basePoint.date))
                }), targetPoint.rate > 0 {
                    let rate = basePoint.rate / targetPoint.rate
                    context.insert(HistoricalRate(
                        baseCurrency: baseName, targetCurrency: targetName,
                        rate: rate, date: basePoint.date
                    ))
                }
            }
        }

        try context.save()
    }
}

/// CoinGecko market chart response
struct CoinGeckoMarketChart: Codable {
    let prices: [[Double]]
}

/// open.er-api.com response (supplementary fiat rates)
struct OpenERResponse: Codable {
    let rates: [String: Double]
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
