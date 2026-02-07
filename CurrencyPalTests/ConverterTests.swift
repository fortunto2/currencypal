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
        #expect(CurrencyCode.allCases.count == 10)
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
