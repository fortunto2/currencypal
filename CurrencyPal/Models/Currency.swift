import Foundation
import SwiftData

/// All supported currencies with display metadata
enum CurrencyCode: String, Codable, CaseIterable, Identifiable {
    case USD, EUR, GBP, JPY, CHF, CAD, AUD, CNY, RUB, TRY

    var id: String { rawValue }

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
        case .RUB: "Russian Ruble"
        case .TRY: "Turkish Lira"
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
        case .RUB: "₽"
        case .TRY: "₺"
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
        case .RUB: "🇷🇺"
        case .TRY: "🇹🇷"
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
