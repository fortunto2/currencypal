import Testing
import Foundation
import SwiftData
@testable import CurrencyPal

/// Amounts are displayed with the locale's decimal separator, so expectations are
/// written with a "." and translated here rather than hard-coding one locale.
@MainActor
func loc(_ value: String) -> String {
    value.replacingOccurrences(of: ".", with: ConverterViewModel.decimalSeparator)
}

// MARK: - Conversion

@MainActor
@Suite("Cross-currency conversion")
struct ConversionTests {

    /// A view model wired with fixed rates — no network, no store.
    private func makeViewModel(
        currencies: [CurrencyCode] = [.USD, .EUR, .JPY, .BTC],
        rates: [CurrencyCode: Double] = [.EUR: 0.92, .JPY: 149.85, .BTC: 0.00001]
    ) -> ConverterViewModel {
        let viewModel = ConverterViewModel()
        viewModel.currencies = currencies
        viewModel.setRates(rates, fetchedAt: .now)
        return viewModel
    }

    @Test("USD input converts every other row")
    func convertsFromUSD() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "100")

        #expect(viewModel.amounts[.EUR] == "92")
        #expect(viewModel.amounts[.JPY] == "14985")
    }

    /// The pivot is USD, so a non-USD active row must still produce correct cross rates.
    @Test("EUR input cross-converts through the USD pivot")
    func convertsFromNonPivotCurrency() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .EUR
        viewModel.userDidType(value: "100")

        // 100 EUR = 100/0.92 USD = 108.70 USD
        #expect(viewModel.amounts[.USD] == loc("108.7"))
        // 100 EUR = 149.85/0.92 * 100 JPY = 16288 JPY
        #expect(viewModel.amounts[.JPY] == "16288")
    }

    @Test("Active row is never overwritten while typing")
    func activeRowKeepsRawInput() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .EUR
        viewModel.userDidType(value: "12.")

        #expect(viewModel.amounts[.EUR] == "12.")
    }

    @Test("Empty input clears the other rows instead of showing stale numbers")
    func emptyInputClearsRows() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "100")
        viewModel.userDidType(value: "")

        #expect(viewModel.amounts[.EUR] == "")
        #expect(viewModel.amounts[.JPY] == "")
    }

    @Test("Zero converts to zero, not to a blank row")
    func zeroConverts() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "0")

        #expect(viewModel.amounts[.EUR] == "0")
        #expect(viewModel.amounts[.JPY] == "0")
    }

    @Test("Comma decimal separator is accepted")
    func commaSeparator() {
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "10,5")

        #expect(viewModel.amounts[.EUR] == loc("9.66"))
    }

    @Test("Currencies without a rate show a dash, not a wrong number")
    func missingRateShowsDash() {
        let viewModel = makeViewModel(
            currencies: [.USD, .EUR, .TRY],
            rates: [.EUR: 0.92] // no TRY rate cached
        )
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "100")

        #expect(viewModel.amounts[.EUR] == "92")
        #expect(viewModel.amounts[.TRY] == "—")
    }

    @Test("Removing the active currency promotes another row")
    func removingActiveCurrency() throws {
        let container = try ModelContainer(
            for: ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let viewModel = makeViewModel()
        viewModel.activeCurrency = .EUR
        viewModel.removeCurrency(.EUR, context: container.mainContext)

        #expect(!viewModel.currencies.contains(.EUR))
        #expect(viewModel.activeCurrency != .EUR)
    }
}

// MARK: - Offline behaviour

@MainActor
@Suite("Offline resilience")
struct OfflineTests {

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// The bug this guards: a failed refresh used to wipe the cache first,
    /// leaving the user with an unusable app the moment the network dropped.
    @Test("Cached rates survive a failed refresh")
    func cacheSurvivesFailedRefresh() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fetchedAt = Date()

        for (code, rate) in [("EUR", 0.92), ("JPY", 149.85)] {
            context.insert(ExchangeRate(baseCurrency: "USD", targetCurrency: code, rate: rate, fetchedAt: fetchedAt))
        }
        try context.save()

        let viewModel = ConverterViewModel()
        viewModel.currencies = [.USD, .EUR, .JPY]
        viewModel.loadCachedRates(context: context)
        viewModel.activeCurrency = .USD
        viewModel.userDidType(value: "100")

        #expect(viewModel.hasRates)
        #expect(viewModel.amounts[.EUR] == "92")

        // Simulate what a failed refresh does: report, keep converting.
        viewModel.statusMessage = ExchangeRateError.offline.errorDescription
        viewModel.recalculate()

        #expect(viewModel.hasRates)
        #expect(viewModel.amounts[.EUR] == "92")
    }

    @Test("Cold start with no cache reports having no rates")
    func coldStartWithoutCache() throws {
        let container = try makeContainer()
        let viewModel = ConverterViewModel()
        viewModel.currencies = [.USD, .EUR]
        viewModel.loadCachedRates(context: container.mainContext)

        #expect(!viewModel.hasRates)
        #expect(viewModel.lastUpdated == nil)
    }

    @Test("Cached rates load back with their original timestamp")
    func cacheRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let fetchedAt = Date(timeIntervalSince1970: 1_770_000_000)
        context.insert(ExchangeRate(baseCurrency: "USD", targetCurrency: "EUR", rate: 0.92, fetchedAt: fetchedAt))
        try context.save()

        let viewModel = ConverterViewModel()
        viewModel.currencies = [.USD, .EUR]
        viewModel.loadCachedRates(context: context)

        #expect(viewModel.lastUpdated == fetchedAt)
        #expect(viewModel.hasRates)
    }

    @Test("Network failures are classified as offline, not as server errors")
    func errorClassification() {
        #expect(ExchangeRateError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(ExchangeRateError.from(URLError(.timedOut)) == .offline)
        #expect(ExchangeRateError.from(URLError(.networkConnectionLost)) == .offline)
        #expect(ExchangeRateError.from(URLError(.badServerResponse)) == .serverUnavailable)
    }
}

// MARK: - Formatting and input

@MainActor
@Suite("Formatting and input handling")
struct FormattingTests {

    @Test("Fiat amounts keep two decimals, yen keeps none")
    func fiatPrecision() {
        #expect(ConverterViewModel.format(92.34, currency: .EUR) == loc("92.34"))
        #expect(ConverterViewModel.format(14985.4, currency: .JPY) == "14985")
        #expect(ConverterViewModel.format(14985.4, currency: .KRW) == "14985")
    }

    /// 0.125 is exactly representable, so this really does test the rounding mode:
    /// bankers' rounding would give 0.12.
    @Test("Halves round up, not to even")
    func roundingMode() {
        #expect(ConverterViewModel.format(0.125, currency: .USD) == loc("0.13"))
        #expect(ConverterViewModel.format(2.5, currency: .JPY) == "3")
    }

    @Test("No grouping separators — the value has to stay editable")
    func noGroupingSeparators() {
        let formatted = ConverterViewModel.format(1_234_567.89, currency: .USD)
        let grouping = Locale.current.groupingSeparator ?? ","
        #expect(!formatted.contains(grouping))
        #expect(!formatted.contains(" "))
        #expect(formatted == loc("1234567.89"))
    }

    /// Crypto spans many orders of magnitude — fixed decimals would print 0.00 for real amounts.
    @Test("Crypto scales precision to the magnitude")
    func cryptoPrecision() {
        #expect(ConverterViewModel.format(0.00001556, currency: .BTC) == loc("0.00001556"))
        #expect(ConverterViewModel.format(0.5, currency: .BTC) == loc("0.5"))
        #expect(ConverterViewModel.format(12.3456789, currency: .BTC) == loc("12.3457"))
        #expect(ConverterViewModel.format(15000.5, currency: .BTC) == loc("15000.5"))
    }

    @Test("Non-finite values degrade to a dash instead of 'inf'")
    func nonFiniteValues() {
        #expect(ConverterViewModel.format(.infinity, currency: .USD) == "—")
        #expect(ConverterViewModel.format(.nan, currency: .USD) == "—")
    }

    @Test("Sanitize strips anything that is not a decimal number")
    func sanitizeInput() {
        #expect(ConverterViewModel.sanitize("12abc3") == "123")
        #expect(ConverterViewModel.sanitize("1,5") == loc("1.5"))
        #expect(ConverterViewModel.sanitize("1.2.3") == loc("1.23"))
        #expect(ConverterViewModel.sanitize("$1 000") == "1000")
        #expect(ConverterViewModel.sanitize("") == "")
    }
}

// MARK: - API parsing

@Suite("API response parsing")
struct APITests {

    @Test("Parse Frankfurter latest response")
    func parseResponse() throws {
        let json = """
        {"base":"USD","date":"2026-02-08","rates":{"EUR":0.9234,"GBP":0.7891}}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FrankfurterResponse.self, from: json)
        #expect(response.base == "USD")
        #expect(response.rates["EUR"] == 0.9234)
        #expect(response.rates.count == 2)
    }

    @Test("Parse Frankfurter time-series response")
    func parseTimeSeries() throws {
        let json = """
        {
            "base": "USD",
            "start_date": "2026-01-09",
            "end_date": "2026-02-08",
            "rates": {
                "2026-01-09": {"EUR": 0.9100},
                "2026-02-08": {"EUR": 0.9234}
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FrankfurterTimeSeriesResponse.self, from: json)
        #expect(response.startDate == "2026-01-09")
        #expect(response.rates["2026-02-08"]?["EUR"] == 0.9234)
    }

    @Test("Parse CoinGecko market chart")
    func parseMarketChart() throws {
        let json = """
        {"prices":[[1770000000000, 64000.5],[1770086400000, 65100.25]]}
        """.data(using: .utf8)!

        let chart = try JSONDecoder().decode(CoinGeckoMarketChart.self, from: json)
        #expect(chart.prices.count == 2)
        #expect(chart.prices[1][1] == 65100.25)
    }

    /// CoinGecko returns an hourly series for a 30-day window; the chart wants days.
    @Test("Hourly series collapses to one point per day, keeping the last reading")
    func collapseToDaily() {
        let day = Date(timeIntervalSince1970: 1_770_000_000)
        let points = [
            RatePoint(date: day, rate: 100),
            RatePoint(date: day.addingTimeInterval(3600), rate: 110),
            RatePoint(date: day.addingTimeInterval(7200), rate: 120),
            RatePoint(date: day.addingTimeInterval(86_400), rate: 200),
        ]

        let daily = ExchangeRateService.collapseToDaily(points)

        #expect(daily.count == 2)
        #expect(daily[0].rate == 120) // last reading of the first day
        #expect(daily[1].rate == 200)
        #expect(daily[0].date < daily[1].date)
    }

    @Test("Parse open.er-api supplementary rates")
    func parseSupplementary() throws {
        let json = """
        {"result":"success","base_code":"USD","rates":{"RUB":96.5,"EUR":0.92}}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenERResponse.self, from: json)
        #expect(response.rates["RUB"] == 96.5)
    }
}

// MARK: - Model metadata

@Suite("Currency metadata and staleness")
struct MetadataTests {

    @Test("Every currency has display metadata")
    func metadataComplete() {
        for code in CurrencyCode.allCases {
            #expect(!code.name.isEmpty)
            #expect(!code.symbol.isEmpty)
            #expect(!code.flag.isEmpty)
        }
        #expect(CurrencyCode.allCases.count == 36)
    }

    @Test("Every crypto has a CoinGecko id and no fiat does")
    func cryptoIdentifiers() {
        for code in CurrencyCode.cryptoCases {
            #expect(code.coinGeckoId != nil)
        }
        for code in CurrencyCode.fiatCases {
            #expect(code.coinGeckoId == nil)
        }
    }

    @Test("Rates go stale after four hours")
    func staleness() {
        let fresh = ExchangeRate(baseCurrency: "USD", targetCurrency: "EUR", rate: 0.92)
        #expect(!fresh.isStale)

        let old = ExchangeRate(
            baseCurrency: "USD", targetCurrency: "EUR", rate: 0.92,
            fetchedAt: Date().addingTimeInterval(-5 * 3600)
        )
        #expect(old.isStale)
    }
}
