import Foundation
import SwiftData
import Observation

/// Main view model for the multi-currency converter screen
@Observable
final class ConverterViewModel {
    var amount: String = "1"
    var fromCurrency: CurrencyCode = .USD
    var selectedTargets: [CurrencyCode] = []
    var convertedAmounts: [CurrencyCode: String] = [:]
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?

    private let service = ExchangeRateService()

    private static let defaultTargets: [CurrencyCode] = [.EUR, .GBP, .JPY]

    /// Load selected currencies from SwiftData, seeding defaults if empty
    @MainActor
    func loadSelectedCurrencies(context: ModelContext) {
        let descriptor = FetchDescriptor<SelectedCurrency>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let saved = (try? context.fetch(descriptor)) ?? []

        if saved.isEmpty {
            // Seed defaults
            for (index, code) in Self.defaultTargets.enumerated() {
                let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: index)
                context.insert(sc)
            }
            try? context.save()
            selectedTargets = Self.defaultTargets
        } else {
            selectedTargets = saved.compactMap { CurrencyCode(rawValue: $0.currencyCode) }
        }
    }

    /// Add a currency to the selected list
    @MainActor
    func addCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard !selectedTargets.contains(code), code != fromCurrency else { return }
        selectedTargets.append(code)
        let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: selectedTargets.count - 1)
        context.insert(sc)
        try? context.save()
        convertAll(context: context)
    }

    /// Remove a currency from the selected list
    @MainActor
    func removeCurrency(_ code: CurrencyCode, context: ModelContext) {
        selectedTargets.removeAll { $0 == code }
        convertedAmounts.removeValue(forKey: code)
        // Delete from persistence
        let codeName = code.rawValue
        try? context.delete(model: SelectedCurrency.self, where: #Predicate<SelectedCurrency> {
            $0.currencyCode == codeName
        })
        // Re-index sort orders
        reindexSortOrders(context: context)
    }

    /// Move a currency within the list (drag-to-reorder)
    @MainActor
    func moveCurrency(from source: IndexSet, to destination: Int, context: ModelContext) {
        selectedTargets.move(fromOffsets: source, toOffset: destination)
        reindexSortOrders(context: context)
    }

    /// Convert the input amount to all selected target currencies
    @MainActor
    func convertAll(context: ModelContext) {
        guard let inputAmount = Double(amount.replacingOccurrences(of: ",", with: ".")) else {
            convertedAmounts = [:]
            return
        }

        let from = fromCurrency.rawValue

        for target in selectedTargets {
            let to = target.rawValue
            let predicate = #Predicate<ExchangeRate> {
                $0.baseCurrency == from && $0.targetCurrency == to
            }
            let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)

            if let rate = try? context.fetch(descriptor).first {
                let result = inputAmount * rate.rate
                convertedAmounts[target] = formatAmount(result, currency: target)
                if lastUpdated == nil || rate.fetchedAt < (lastUpdated ?? .distantFuture) {
                    lastUpdated = rate.fetchedAt
                }
            } else {
                convertedAmounts[target] = "—"
            }
        }
    }

    /// Refresh rates from API
    @MainActor
    func refreshRates(context: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            try await service.updateCache(base: fromCurrency, context: context)
            convertAll(context: context)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Check if cache is stale and refresh if needed
    @MainActor
    func refreshIfNeeded(context: ModelContext) async {
        let from = fromCurrency.rawValue
        let predicate = #Predicate<ExchangeRate> { $0.baseCurrency == from }
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)

        let rates = (try? context.fetch(descriptor)) ?? []

        if rates.isEmpty || rates.first?.isStale == true {
            await refreshRates(context: context)
        } else {
            convertAll(context: context)
        }
    }

    /// Currencies available to add (not already selected and not the base)
    var availableCurrencies: [CurrencyCode] {
        CurrencyCode.allCases.filter { $0 != fromCurrency && !selectedTargets.contains($0) }
    }

    // MARK: - Private

    private func reindexSortOrders(context: ModelContext) {
        // Delete all and re-insert with correct sort orders
        try? context.delete(model: SelectedCurrency.self)
        for (index, code) in selectedTargets.enumerated() {
            let sc = SelectedCurrency(currencyCode: code.rawValue, sortOrder: index)
            context.insert(sc)
        }
        try? context.save()
    }

    func formatAmount(_ value: Double, currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == .JPY ? 0 : 2
        formatter.minimumFractionDigits = currency == .JPY ? 0 : 2
        formatter.groupingSeparator = " "
        return "\(currency.symbol) \(formatter.string(from: NSNumber(value: value)) ?? "—")"
    }
}
