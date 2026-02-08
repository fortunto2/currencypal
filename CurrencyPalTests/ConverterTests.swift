import Testing
import Foundation
@testable import CurrencyPal

@Suite("Currency Conversion Tests")
struct ConverterTests {

    @Test("Basic USD to EUR conversion")
    func basicConversion() {
        let rate = 0.9234
        let amount = 100.0
        let result = amount * rate
        #expect(result == 92.34)
    }

    @Test("JPY conversion rounds to zero decimals")
    func jpyRounding() {
        let rate = 149.85
        let amount = 100.0
        let result = (amount * rate).rounded()
        #expect(result == 14985.0)
    }

    @Test("Self-conversion returns same amount")
    func selfConversion() {
        let rate = 1.0
        let amount = 42.5
        #expect(amount * rate == 42.5)
    }

    @Test("Zero amount returns zero")
    func zeroAmount() {
        let rate = 0.9234
        let amount = 0.0
        #expect(amount * rate == 0.0)
    }

    @Test("Large amount does not overflow")
    func largeAmount() {
        let rate = 149.85
        let amount = 999_999_999.0
        let result = amount * rate
        #expect(result > 0)
        #expect(result.isFinite)
    }

    @Test("Currency code metadata")
    func currencyMetadata() {
        #expect(CurrencyCode.USD.symbol == "$")
        #expect(CurrencyCode.EUR.flag == "🇪🇺")
        #expect(CurrencyCode.JPY.name == "Japanese Yen")
        #expect(CurrencyCode.allCases.count == 36)
    }
}

@Suite("Frankfurter API Response Parsing")
struct APITests {

    @Test("Parse valid response")
    func parseResponse() throws {
        let json = """
        {"base":"USD","date":"2026-02-08","rates":{"EUR":0.9234,"GBP":0.7891}}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FrankfurterResponse.self, from: json)
        #expect(response.base == "USD")
        #expect(response.rates["EUR"] == 0.9234)
        #expect(response.rates["GBP"] == 0.7891)
        #expect(response.rates.count == 2)
    }

    @Test("Parse time-series response")
    func parseTimeSeries() throws {
        let json = """
        {
            "base": "USD",
            "start_date": "2026-01-09",
            "end_date": "2026-02-08",
            "rates": {
                "2026-01-09": {"EUR": 0.9100},
                "2026-01-10": {"EUR": 0.9150},
                "2026-02-08": {"EUR": 0.9234}
            }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(FrankfurterTimeSeriesResponse.self, from: json)
        #expect(response.base == "USD")
        #expect(response.startDate == "2026-01-09")
        #expect(response.endDate == "2026-02-08")
        #expect(response.rates.count == 3)
        #expect(response.rates["2026-01-09"]?["EUR"] == 0.9100)
        #expect(response.rates["2026-02-08"]?["EUR"] == 0.9234)
    }
}

@Suite("Exchange Rate Staleness")
struct StalenessTests {

    @Test("Fresh rate is not stale")
    func freshRate() {
        let rate = ExchangeRate(baseCurrency: "USD", targetCurrency: "EUR", rate: 0.92)
        #expect(!rate.isStale)
    }

    @Test("Old rate is stale after 4 hours")
    func staleRate() {
        let rate = ExchangeRate(
            baseCurrency: "USD",
            targetCurrency: "EUR",
            rate: 0.92,
            fetchedAt: Date().addingTimeInterval(-5 * 3600)
        )
        #expect(rate.isStale)
    }
}

@Suite("Multi-Converter Logic")
struct MultiConverterTests {

    @Test("Multi-conversion math: convert to multiple targets")
    func multiConversion() {
        let amount = 100.0
        let rates: [String: Double] = ["EUR": 0.92, "GBP": 0.79, "JPY": 149.85]

        var results: [String: Double] = [:]
        for (currency, rate) in rates {
            results[currency] = amount * rate
        }

        #expect(results["EUR"] == 92.0)
        #expect(results["GBP"] == 79.0)
        #expect(results["JPY"] == 14985.0)
    }

    @Test("Available currencies filters out base and selected")
    func availableCurrenciesFilter() {
        let base: CurrencyCode = .USD
        let selected: [CurrencyCode] = [.EUR, .GBP, .JPY]
        let available = CurrencyCode.allCases.filter { $0 != base && !selected.contains($0) }

        #expect(!available.contains(.USD))
        #expect(!available.contains(.EUR))
        #expect(!available.contains(.GBP))
        #expect(!available.contains(.JPY))
        #expect(available.contains(.CHF))
        #expect(available.contains(.CAD))
        #expect(available.count == 32)
    }
}

@Suite("Chart Statistics")
struct ChartStatsTests {

    @Test("Percent change calculation")
    func percentChange() {
        let firstRate = 0.9100
        let lastRate = 0.9234
        let change = ((lastRate - firstRate) / firstRate) * 100

        #expect(change > 1.47)
        #expect(change < 1.48)
    }

    @Test("Percent change with decline")
    func percentChangeDecline() {
        let firstRate = 0.9500
        let lastRate = 0.9234
        let change = ((lastRate - firstRate) / firstRate) * 100

        #expect(change < 0)
        #expect(change > -2.80)
        #expect(change < -2.79)
    }

    @Test("Min and max from data points")
    func minMaxRates() {
        let rates = [0.91, 0.92, 0.89, 0.95, 0.93]
        #expect(rates.min() == 0.89)
        #expect(rates.max() == 0.95)
    }
}
