import Foundation
import SwiftData

/// Immutable set of USD-based rates fetched from the network.
/// `rates["EUR"] == 0.92` means "1 USD = 0.92 EUR".
struct RateSnapshot: Sendable {
    let rates: [String: Double]
    let fetchedAt: Date
}

/// Fetches exchange rates from Frankfurter (fiat), CoinGecko (crypto) and
/// open.er-api.com (fiat outside the ECB set, e.g. RUB).
///
/// Networking only — persistence is the caller's job. That split is deliberate:
/// the cache must never be cleared before a fetch has actually succeeded,
/// otherwise a failed refresh leaves the app with nothing to show offline.
actor ExchangeRateService {
    private let frankfurterBaseURL = URL(string: "https://api.frankfurter.dev/v1/latest")!
    private let timeSeriesBaseURL = "https://api.frankfurter.dev/v1/"
    private let coinGeckoBaseURL = "https://api.coingecko.com/api/v3"

    /// Short timeouts: a converter that hangs for the default 60s reads as broken.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 20
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    // MARK: - Transport

    /// CoinGecko's keyless tier starts returning 429 after a handful of calls, which
    /// is easy to hit by opening two charts in a row. One backoff retry turns that
    /// from a dead screen into a short wait.
    private func get(_ url: URL, retriesOnRateLimit: Int = 1) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse else {
                throw ExchangeRateError.serverUnavailable
            }

            if http.statusCode == 429 {
                guard retriesOnRateLimit > 0 else { throw ExchangeRateError.rateLimited }
                let retryAfter = (http.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 2
                try await Task.sleep(for: .seconds(min(retryAfter, 5)))
                return try await get(url, retriesOnRateLimit: retriesOnRateLimit - 1)
            }

            guard http.statusCode == 200 else {
                throw ExchangeRateError.serverUnavailable
            }
            return data
        } catch let error as ExchangeRateError {
            throw error
        } catch is CancellationError {
            throw ExchangeRateError.serverUnavailable
        } catch {
            throw ExchangeRateError.from(error)
        }
    }

    // MARK: - Frankfurter (Fiat)

    /// Fetch latest fiat rates from Frankfurter API
    func fetchRates(base: CurrencyCode) async throws -> FrankfurterResponse {
        var components = URLComponents(url: frankfurterBaseURL, resolvingAgainstBaseURL: false)!
        let baseCode = (base.isCrypto || base.isSupplementaryFiat) ? CurrencyCode.USD : base
        components.queryItems = [URLQueryItem(name: "base", value: baseCode.rawValue)]

        let data = try await get(components.url!)
        return try JSONDecoder().decode(FrankfurterResponse.self, from: data)
    }

    // MARK: - CoinGecko (Crypto)

    /// Fetch crypto prices in a given fiat currency from CoinGecko
    func fetchCryptoPrices(vsCurrency: String = "usd") async throws -> [String: Double] {
        let ids = CurrencyCode.cryptoCases.compactMap(\.coinGeckoId).joined(separator: ",")
        let vs = vsCurrency.lowercased()
        guard let url = URL(string: "\(coinGeckoBaseURL)/simple/price?ids=\(ids)&vs_currencies=\(vs)") else {
            throw ExchangeRateError.serverUnavailable
        }

        let data = try await get(url)

        // Response: {"bitcoin":{"usd":97000},"ethereum":{"usd":3200},...}
        let json = try JSONDecoder().decode([String: [String: Double]].self, from: data)
        var prices: [String: Double] = [:]
        for crypto in CurrencyCode.cryptoCases {
            if let geckoId = crypto.coinGeckoId, let price = json[geckoId]?[vs], price > 0 {
                prices[crypto.rawValue] = price
            }
        }
        return prices
    }

    // MARK: - Supplementary Fiat (RUB etc.)

    /// Fetch rates from open.er-api.com for currencies not covered by the ECB (e.g. RUB)
    func fetchSupplementaryRates(base: String = "USD") async throws -> [String: Double] {
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)") else {
            throw ExchangeRateError.serverUnavailable
        }

        let data = try await get(url)

        // Response: {"result":"success","base_code":"USD","rates":{"RUB":96.5,...}}
        return try JSONDecoder().decode(OpenERResponse.self, from: data).rates
    }

    // MARK: - Snapshot

    /// Fetch every rate the app needs, expressed against USD, in one pass.
    ///
    /// The three sources run concurrently. Frankfurter is required — without fiat
    /// rates there is no usable snapshot. Crypto and supplementary fiat are
    /// best-effort: a CoinGecko outage should not cost the user EUR and GBP.
    func fetchUSDSnapshot() async throws -> RateSnapshot {
        async let fiatTask = fetchRates(base: .USD)
        async let cryptoTask = fetchCryptoPrices(vsCurrency: "usd")
        async let supplementaryTask = fetchSupplementaryRates(base: "USD")

        let crypto = try? await cryptoTask
        let supplementary = try? await supplementaryTask
        let fiat = try await fiatTask

        var rates: [String: Double] = [:]

        // Frankfurter already returns "1 USD = X target"
        for (code, rate) in fiat.rates where rate > 0 {
            rates[code] = rate
        }

        // CoinGecko returns "1 crypto = X USD", we store the inverse
        for (code, priceInUSD) in crypto ?? [:] where priceInUSD > 0 {
            rates[code] = 1.0 / priceInUSD
        }

        // open.er-api returns "1 USD = X target" — only used for codes the ECB lacks
        for code in CurrencyCode.allCases where code.isSupplementaryFiat {
            if let rate = supplementary?[code.rawValue], rate > 0 {
                rates[code.rawValue] = rate
            }
        }

        rates[CurrencyCode.USD.rawValue] = 1.0

        guard rates.count > 1 else { throw ExchangeRateError.noData }
        return RateSnapshot(rates: rates, fetchedAt: Date())
    }

    // MARK: - Time Series (charts)

    /// Fetch time-series rates for a fiat currency pair
    func fetchTimeSeries(
        base: CurrencyCode,
        symbol: CurrencyCode,
        startDate: Date,
        endDate: Date
    ) async throws -> FrankfurterTimeSeriesResponse {
        let start = Self.dateFormatter.string(from: startDate)
        let end = Self.dateFormatter.string(from: endDate)
        let urlString = "\(timeSeriesBaseURL)\(start)..\(end)?base=\(base.rawValue)&symbols=\(symbol.rawValue)"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.serverUnavailable
        }

        let data = try await get(url)
        return try JSONDecoder().decode(FrankfurterTimeSeriesResponse.self, from: data)
    }

    /// Fetch CoinGecko market chart for a crypto, thinned to one point per day.
    ///
    /// `interval=daily` is deliberately omitted: on the keyless tier it answers with
    /// a stale window (months behind), while the default granularity is current.
    /// The hourly series it returns is collapsed here instead.
    func fetchCryptoHistory(coinId: String, days: Int = 30) async throws -> [RatePoint] {
        let urlString = "\(coinGeckoBaseURL)/coins/\(coinId)/market_chart?vs_currency=usd&days=\(days)"

        guard let url = URL(string: urlString) else {
            throw ExchangeRateError.serverUnavailable
        }

        let data = try await get(url)

        // Response: {"prices":[[timestamp_ms, price], ...], ...}
        let json = try JSONDecoder().decode(CoinGeckoMarketChart.self, from: data)
        let points = json.prices.compactMap { pair -> RatePoint? in
            guard pair.count == 2, pair[1] > 0 else { return nil }
            return RatePoint(date: Date(timeIntervalSince1970: pair[0] / 1000), rate: pair[1])
        }
        return Self.collapseToDaily(points)
    }

    /// Keep the last observation of each calendar day, in chronological order.
    static func collapseToDaily(_ points: [RatePoint]) -> [RatePoint] {
        let calendar = Calendar(identifier: .gregorian)
        var lastPerDay: [Date: RatePoint] = [:]
        for point in points {
            let day = calendar.startOfDay(for: point.date)
            if let existing = lastPerDay[day], existing.date >= point.date { continue }
            lastPerDay[day] = point
        }
        return lastPerDay.values.sorted { $0.date < $1.date }
    }

    /// Build a 30-day series for any pair, fiat or crypto, without touching the store.
    func fetchHistory(base: CurrencyCode, target: CurrencyCode, days: Int = 30) async throws -> [RatePoint] {
        if !base.isCrypto && !target.isCrypto {
            // Frankfurter has no RUB — pivot through USD when either side is supplementary
            if base.isSupplementaryFiat || target.isSupplementaryFiat {
                throw ExchangeRateError.noData
            }
            let endDate = Date()
            let startDate = Calendar.current.date(byAdding: .day, value: -days, to: endDate)!
            let response = try await fetchTimeSeries(base: base, symbol: target, startDate: startDate, endDate: endDate)

            return response.rates.compactMap { dateString, ratesDict in
                guard let rate = ratesDict[target.rawValue], rate > 0,
                      let date = Self.dateFormatter.date(from: dateString) else { return nil }
                return RatePoint(date: date, rate: rate)
            }
            .sorted { $0.date < $1.date }
        }

        if !base.isCrypto && target.isCrypto {
            // Fiat → crypto: crypto history is in USD, scale by today's USD→fiat rate
            guard let geckoId = target.coinGeckoId else { throw ExchangeRateError.noData }
            let history = try await fetchCryptoHistory(coinId: geckoId, days: days)
            let usdPerBase = try await usdRate(for: base)

            return history.map { RatePoint(date: $0.date, rate: usdPerBase / $0.rate) }
        }

        if base.isCrypto && !target.isCrypto {
            guard let geckoId = base.coinGeckoId else { throw ExchangeRateError.noData }
            let history = try await fetchCryptoHistory(coinId: geckoId, days: days)
            let usdPerTarget = try await usdRate(for: target)

            return history.map { RatePoint(date: $0.date, rate: $0.rate * usdPerTarget) }
        }

        // Crypto → crypto: align both USD series by calendar day
        guard let baseId = base.coinGeckoId, let targetId = target.coinGeckoId else {
            throw ExchangeRateError.noData
        }
        async let baseTask = fetchCryptoHistory(coinId: baseId, days: days)
        async let targetTask = fetchCryptoHistory(coinId: targetId, days: days)
        let baseHistory = try await baseTask
        let targetHistory = try await targetTask

        // Index by day so the join is O(n), not O(n²)
        let calendar = Calendar(identifier: .gregorian)
        var targetByDay: [Date: Double] = [:]
        for point in targetHistory {
            targetByDay[calendar.startOfDay(for: point.date)] = point.rate
        }

        return baseHistory.compactMap { point in
            guard let targetRate = targetByDay[calendar.startOfDay(for: point.date)], targetRate > 0 else {
                return nil
            }
            return RatePoint(date: point.date, rate: point.rate / targetRate)
        }
    }

    /// "1 `currency` = X USD", for the currencies charts can reach.
    private func usdRate(for currency: CurrencyCode) async throws -> Double {
        if currency == .USD { return 1.0 }
        if currency.isSupplementaryFiat {
            let rates = try await fetchSupplementaryRates(base: "USD")
            guard let perUSD = rates[currency.rawValue], perUSD > 0 else { throw ExchangeRateError.noData }
            return 1.0 / perUSD
        }
        let response = try await fetchRates(base: .USD)
        guard let perUSD = response.rates[currency.rawValue], perUSD > 0 else { throw ExchangeRateError.noData }
        return 1.0 / perUSD
    }
}

/// One point of a rate series.
struct RatePoint: Sendable, Equatable {
    let date: Date
    let rate: Double
}

/// CoinGecko market chart response
struct CoinGeckoMarketChart: Codable {
    let prices: [[Double]]
}

/// open.er-api.com response (supplementary fiat rates)
struct OpenERResponse: Codable {
    let rates: [String: Double]
}

enum ExchangeRateError: LocalizedError, Equatable {
    /// The device could not reach the network at all.
    case offline
    /// The network is up but the rate provider did not answer usefully.
    case serverUnavailable
    /// The provider is throttling us (CoinGecko's keyless tier is stingy).
    case rateLimited
    case noData

    static func from(_ error: Error) -> ExchangeRateError {
        guard let urlError = error as? URLError else { return .serverUnavailable }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .timedOut,
             .internationalRoamingOff, .callIsActive, .secureConnectionFailed:
            return .offline
        default:
            return .serverUnavailable
        }
    }

    var errorDescription: String? {
        switch self {
        case .offline: String(localized: "No connection — showing saved rates.")
        case .serverUnavailable: String(localized: "Rate service unavailable — showing saved rates.")
        case .rateLimited: String(localized: "Too many requests — try again in a moment.")
        case .noData: String(localized: "No saved rates yet. Connect once to get started.")
        }
    }
}
