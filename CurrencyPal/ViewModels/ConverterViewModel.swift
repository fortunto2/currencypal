import Foundation
import SwiftData
import Observation

/// Multi-currency converter. Any row is editable — all others recalculate instantly.
/// Uses USD as pivot currency for cross-calculation (no re-fetch needed when switching rows).
@Observable
final class ConverterViewModel {
    var activeCurrency: CurrencyCode = .USD
    var amounts: [CurrencyCode: String] = [:]
    var currencies: [CurrencyCode] = []
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?

    private let service = ExchangeRateService()

    private static let defaultCurrencies: [CurrencyCode] = [.USD, .EUR, .GBP, .JPY, .RUB, .BTC]

    // MARK: - Lifecycle

    @MainActor
    func loadCurrencies(context: ModelContext) {
        let descriptor = FetchDescriptor<SelectedCurrency>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let saved = (try? context.fetch(descriptor)) ?? []

        if saved.isEmpty {
            for (index, code) in Self.defaultCurrencies.enumerated() {
                context.insert(SelectedCurrency(currencyCode: code.rawValue, sortOrder: index))
            }
            try? context.save()
            currencies = Self.defaultCurrencies
        } else {
            currencies = saved.compactMap { CurrencyCode(rawValue: $0.currencyCode) }
        }

        if amounts[activeCurrency] == nil {
            amounts[activeCurrency] = "1"
        }
    }

    // MARK: - User Input

    /// User tapped a row — make it active, keep value visible (don't clear yet)
    @MainActor
    func userDidActivate(currency: CurrencyCode, context: ModelContext) {
        guard activeCurrency != currency else { return }
        activeCurrency = currency
    }

    /// User typed a value in the active row
    @MainActor
    func userDidType(value: String, context: ModelContext) {
        amounts[activeCurrency] = value
        recalculate(context: context)
    }

    /// Cross-calculate all amounts using USD as pivot.
    /// If active is EUR and we have USD→EUR=0.92, USD→JPY=149.85,
    /// then EUR→JPY = 149.85 / 0.92 = 162.88
    @MainActor
    func recalculate(context: ModelContext) {
        let raw = amounts[activeCurrency] ?? "0"
        guard let inputAmount = Double(raw.replacingOccurrences(of: ",", with: ".")),
              inputAmount > 0 else {
            for code in currencies where code != activeCurrency {
                amounts[code] = ""
            }
            return
        }

        let activeUSDRate = usdRate(for: activeCurrency, context: context)
        guard activeUSDRate > 0 else {
            for code in currencies where code != activeCurrency {
                amounts[code] = "—"
            }
            return
        }

        for target in currencies where target != activeCurrency {
            let targetUSDRate = usdRate(for: target, context: context)
            if targetUSDRate > 0 {
                // X→Y = (USD→Y) / (USD→X) where USD→X means "1 USD = X units"
                let rate = targetUSDRate / activeUSDRate
                let result = inputAmount * rate
                amounts[target] = formatRaw(result, currency: target)
                // Track freshness from the rate entry
                updateFreshness(for: target, context: context)
            } else {
                amounts[target] = "—"
            }
        }
    }

    /// Get "1 USD = ? target" rate from cache
    private func usdRate(for currency: CurrencyCode, context: ModelContext) -> Double {
        if currency == .USD { return 1.0 }
        let usd = "USD"
        let target = currency.rawValue
        let predicate = #Predicate<ExchangeRate> {
            $0.baseCurrency == usd && $0.targetCurrency == target
        }
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)
        return (try? context.fetch(descriptor).first?.rate) ?? 0
    }

    private func updateFreshness(for currency: CurrencyCode, context: ModelContext) {
        let usd = "USD"
        let target = currency.rawValue
        let predicate = #Predicate<ExchangeRate> {
            $0.baseCurrency == usd && $0.targetCurrency == target
        }
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)
        if let rate = try? context.fetch(descriptor).first {
            if lastUpdated == nil || rate.fetchedAt < (lastUpdated ?? .distantFuture) {
                lastUpdated = rate.fetchedAt
            }
        }
    }

    // MARK: - List Management

    @MainActor
    func addCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard !currencies.contains(code) else { return }
        currencies.append(code)
        context.insert(SelectedCurrency(currencyCode: code.rawValue, sortOrder: currencies.count - 1))
        try? context.save()
        recalculate(context: context)
    }

    @MainActor
    func removeCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard currencies.count > 2 else { return }
        currencies.removeAll { $0 == code }
        amounts.removeValue(forKey: code)
        let codeName = code.rawValue
        try? context.delete(model: SelectedCurrency.self, where: #Predicate<SelectedCurrency> {
            $0.currencyCode == codeName
        })
        if activeCurrency == code {
            activeCurrency = currencies.first ?? .USD
        }
        reindexSortOrders(context: context)
    }

    @MainActor
    func moveCurrency(from source: IndexSet, to destination: Int, context: ModelContext) {
        currencies.move(fromOffsets: source, toOffset: destination)
        reindexSortOrders(context: context)
    }

    var availableCurrencies: [CurrencyCode] {
        CurrencyCode.allCases.filter { !currencies.contains($0) }
    }

    // MARK: - Network

    /// Always fetch USD-based rates (our pivot), so cross-calc works for any active currency
    @MainActor
    func refreshRates(context: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            try await service.updateCache(base: .USD, context: context)
            recalculate(context: context)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func refreshIfNeeded(context: ModelContext) async {
        let usd = "USD"
        let predicate = #Predicate<ExchangeRate> { $0.baseCurrency == usd }
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)

        let rates = (try? context.fetch(descriptor)) ?? []

        if rates.isEmpty || rates.first?.isStale == true {
            await refreshRates(context: context)
        } else {
            recalculate(context: context)
        }
    }

    // MARK: - Private

    private func reindexSortOrders(context: ModelContext) {
        try? context.delete(model: SelectedCurrency.self)
        for (index, code) in currencies.enumerated() {
            context.insert(SelectedCurrency(currencyCode: code.rawValue, sortOrder: index))
        }
        try? context.save()
    }

    func formatRaw(_ value: Double, currency: CurrencyCode) -> String {
        if currency.isCrypto {
            // Crypto needs more precision
            let formatted = String(format: "%.8f", value)
            // Trim trailing zeros but keep at least one decimal
            let trimmed = formatted.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
            return trimmed.hasSuffix(".") ? trimmed + "0" : trimmed
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == .JPY || currency == .KRW ? 0 : 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
