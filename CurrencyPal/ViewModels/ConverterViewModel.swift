import Foundation
import SwiftData
import Observation

/// Main view model for the multi-currency converter screen.
/// Any row can be the active input — tap it, type a number, all others recalculate.
@Observable
final class ConverterViewModel {
    /// Which currency the user is currently typing into
    var activeCurrency: CurrencyCode = .USD
    /// Raw text amounts for every currency in the list
    var amounts: [CurrencyCode: String] = [:]
    var currencies: [CurrencyCode] = []
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?

    private let service = ExchangeRateService()

    private static let defaultCurrencies: [CurrencyCode] = [.USD, .EUR, .GBP, .JPY, .RUB, .BTC]

    // MARK: - Lifecycle

    /// Load currency list from SwiftData, seeding defaults if empty
    @MainActor
    func loadCurrencies(context: ModelContext) {
        let descriptor = FetchDescriptor<SelectedCurrency>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let saved = (try? context.fetch(descriptor)) ?? []

        if saved.isEmpty {
            for (index, code) in Self.defaultCurrencies.enumerated() {
                let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: index)
                context.insert(sc)
            }
            try? context.save()
            currencies = Self.defaultCurrencies
        } else {
            currencies = saved.compactMap { CurrencyCode(rawValue: $0.currencyCode) }
        }

        // Set initial amount for active currency
        if amounts[activeCurrency] == nil {
            amounts[activeCurrency] = "1"
        }
    }

    // MARK: - User Input

    /// Called when the user types a new amount in a row
    @MainActor
    func userDidEditAmount(for currency: CurrencyCode, newValue: String, context: ModelContext) {
        activeCurrency = currency
        amounts[currency] = newValue
        recalculate(context: context)
    }

    /// Recalculate all amounts based on active currency
    @MainActor
    func recalculate(context: ModelContext) {
        let raw = amounts[activeCurrency] ?? "0"
        guard let inputAmount = Double(raw.replacingOccurrences(of: ",", with: ".")) else {
            for code in currencies where code != activeCurrency {
                amounts[code] = ""
            }
            return
        }

        let from = activeCurrency.rawValue

        for target in currencies where target != activeCurrency {
            let to = target.rawValue
            let predicate = #Predicate<ExchangeRate> {
                $0.baseCurrency == from && $0.targetCurrency == to
            }
            let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)

            if let rate = try? context.fetch(descriptor).first {
                let result = inputAmount * rate.rate
                amounts[target] = formatRawAmount(result, currency: target)
                if lastUpdated == nil || rate.fetchedAt < (lastUpdated ?? .distantFuture) {
                    lastUpdated = rate.fetchedAt
                }
            } else {
                amounts[target] = "—"
            }
        }
    }

    // MARK: - List Management

    @MainActor
    func addCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard !currencies.contains(code) else { return }
        currencies.append(code)
        let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: currencies.count - 1)
        context.insert(sc)
        try? context.save()
        recalculate(context: context)
    }

    @MainActor
    func removeCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard currencies.count > 2 else { return } // need at least 2
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

    @MainActor
    func refreshRates(context: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            try await service.updateCache(base: activeCurrency, context: context)
            recalculate(context: context)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    func refreshIfNeeded(context: ModelContext) async {
        let from = activeCurrency.rawValue
        let predicate = #Predicate<ExchangeRate> { $0.baseCurrency == from }
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
            let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: index)
            context.insert(sc)
        }
        try? context.save()
    }

    /// Format a number for display in the text field (no currency symbol — just digits)
    func formatRawAmount(_ value: Double, currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == .JPY ? 0 : 2
        formatter.minimumFractionDigits = 0
        formatter.groupingSeparator = ""
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Format with currency symbol for display
    func formatDisplayAmount(_ value: String, currency: CurrencyCode) -> String {
        "\(currency.symbol) \(value)"
    }
}
