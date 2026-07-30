import Foundation
import SwiftData

/// All supported currencies with display metadata
enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    // Fiat — Frankfurter (ECB) supported
    case USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, TRY
    case BRL, CZK, DKK, HKD, HUF, IDR, ILS, INR, ISK
    case KRW, MXN, MYR, NOK, NZD, PHP, PLN, RON, SEK, SGD, THB, ZAR
    // Fiat — supplementary (not in ECB, fetched from open.er-api.com)
    case RUB
    // Crypto — CoinGecko
    case BTC, ETH, SOL, XRP, BNB

    var id: String { rawValue }

    var isCrypto: Bool {
        switch self {
        case .BTC, .ETH, .SOL, .XRP, .BNB: true
        default: false
        }
    }

    /// Currencies not in Frankfurter/ECB, fetched from alternative API
    var isSupplementaryFiat: Bool {
        switch self {
        case .RUB: true
        default: false
        }
    }

    /// CoinGecko API id for crypto currencies
    var coinGeckoId: String? {
        switch self {
        case .BTC: "bitcoin"
        case .ETH: "ethereum"
        case .SOL: "solana"
        case .XRP: "ripple"
        case .BNB: "binancecoin"
        default: nil
        }
    }

    static var fiatCases: [CurrencyCode] {
        allCases.filter { !$0.isCrypto }
    }

    static var cryptoCases: [CurrencyCode] {
        allCases.filter { $0.isCrypto }
    }

    var name: String {
        switch self {
        case .USD: "US Dollar"
        case .EUR: "Euro"
        case .GBP: "British Pound"
        case .JPY: "Japanese Yen"
        case .CHF: "Swiss Franc"
        case .CAD: "Canadian Dollar"
        case .AUD: "Australian Dollar"
        case .CNY: "Chinese Yuan"
        case .TRY: "Turkish Lira"
        case .BRL: "Brazilian Real"
        case .CZK: "Czech Koruna"
        case .DKK: "Danish Krone"
        case .HKD: "Hong Kong Dollar"
        case .HUF: "Hungarian Forint"
        case .IDR: "Indonesian Rupiah"
        case .ILS: "Israeli Shekel"
        case .INR: "Indian Rupee"
        case .ISK: "Icelandic Krona"
        case .KRW: "South Korean Won"
        case .MXN: "Mexican Peso"
        case .MYR: "Malaysian Ringgit"
        case .NOK: "Norwegian Krone"
        case .NZD: "New Zealand Dollar"
        case .PHP: "Philippine Peso"
        case .PLN: "Polish Zloty"
        case .RON: "Romanian Leu"
        case .SEK: "Swedish Krona"
        case .SGD: "Singapore Dollar"
        case .THB: "Thai Baht"
        case .ZAR: "South African Rand"
        case .RUB: "Russian Ruble"
        case .BTC: "Bitcoin"
        case .ETH: "Ethereum"
        case .SOL: "Solana"
        case .XRP: "XRP"
        case .BNB: "BNB"
        }
    }

    var symbol: String {
        switch self {
        case .USD: "$"
        case .EUR: "€"
        case .GBP: "£"
        case .JPY: "¥"
        case .CHF: "CHF"
        case .CAD: "C$"
        case .AUD: "A$"
        case .CNY: "¥"
        case .TRY: "₺"
        case .BRL: "R$"
        case .CZK: "Kč"
        case .DKK: "kr"
        case .HKD: "HK$"
        case .HUF: "Ft"
        case .IDR: "Rp"
        case .ILS: "₪"
        case .INR: "₹"
        case .ISK: "kr"
        case .KRW: "₩"
        case .MXN: "MX$"
        case .MYR: "RM"
        case .NOK: "kr"
        case .NZD: "NZ$"
        case .PHP: "₱"
        case .PLN: "zł"
        case .RON: "lei"
        case .SEK: "kr"
        case .SGD: "S$"
        case .THB: "฿"
        case .ZAR: "R"
        case .RUB: "₽"
        case .BTC: "₿"
        case .ETH: "Ξ"
        case .SOL: "SOL"
        case .XRP: "XRP"
        case .BNB: "BNB"
        }
    }

    var flag: String {
        switch self {
        case .USD: "🇺🇸"
        case .EUR: "🇪🇺"
        case .GBP: "🇬🇧"
        case .JPY: "🇯🇵"
        case .CHF: "🇨🇭"
        case .CAD: "🇨🇦"
        case .AUD: "🇦🇺"
        case .CNY: "🇨🇳"
        case .TRY: "🇹🇷"
        case .BRL: "🇧🇷"
        case .CZK: "🇨🇿"
        case .DKK: "🇩🇰"
        case .HKD: "🇭🇰"
        case .HUF: "🇭🇺"
        case .IDR: "🇮🇩"
        case .ILS: "🇮🇱"
        case .INR: "🇮🇳"
        case .ISK: "🇮🇸"
        case .KRW: "🇰🇷"
        case .MXN: "🇲🇽"
        case .MYR: "🇲🇾"
        case .NOK: "🇳🇴"
        case .NZD: "🇳🇿"
        case .PHP: "🇵🇭"
        case .PLN: "🇵🇱"
        case .RON: "🇷🇴"
        case .SEK: "🇸🇪"
        case .SGD: "🇸🇬"
        case .THB: "🇹🇭"
        case .ZAR: "🇿🇦"
        case .RUB: "🇷🇺"
        case .BTC: "₿"
        case .ETH: "⟠"
        case .SOL: "◎"
        case .XRP: "✕"
        case .BNB: "⬡"
        }
    }
}

/// Cached exchange rate stored in SwiftData
@Model
final class ExchangeRate {
    var baseCurrency: String
    var targetCurrency: String
    var rate: Double
    var fetchedAt: Date

    init(baseCurrency: String, targetCurrency: String, rate: Double, fetchedAt: Date = .now) {
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.rate = rate
        self.fetchedAt = fetchedAt
    }

    var isStale: Bool {
        fetchedAt.timeIntervalSinceNow < -4 * 3600 // older than 4 hours
    }
}

/// User-selected target currency for multi-converter list
@Model
final class SelectedCurrency {
    var currencyCode: String
    var sortOrder: Int

    init(currencyCode: String, sortOrder: Int) {
        self.currencyCode = currencyCode
        self.sortOrder = sortOrder
    }
}

/// Cached historical rate for chart display
@Model
final class HistoricalRate {
    var baseCurrency: String
    var targetCurrency: String
    var rate: Double
    var date: Date

    init(baseCurrency: String, targetCurrency: String, rate: Double, date: Date) {
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.rate = rate
        self.date = date
    }
}
