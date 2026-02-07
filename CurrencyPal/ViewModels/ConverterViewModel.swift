import Foundation
import SwiftData
import Observation

/// Main view model for the currency converter screen
@Observable
final class ConverterViewModel {
    var amount: String = "1"
    var fromCurrency: CurrencyCode = .USD
    var toCurrency: CurrencyCode = .EUR
    var convertedAmount: String = "—"
    var rateInfo: String = ""
    var lastUpdated: Date?
    var isLoading = false
    var errorMessage: String?

    private let service = ExchangeRateService()

    /// Convert using cached rates from SwiftData
    @MainActor
    func convert(context: ModelContext) {
        guard let inputAmount = Double(amount.replacingOccurrences(of: ",", with: ".")) else {
            convertedAmount = "—"
            rateInfo = ""
            return
        }

        let from = fromCurrency.rawValue
        let to = toCurrency.rawValue

        let predicate = #Predicate<ExchangeRate> {
            $0.baseCurrency == from && $0.targetCurrency == to
        }
        let descriptor = FetchDescriptor<ExchangeRate>(predicate: predicate)

        guard let rate = try? context.fetch(descriptor).first else {
            convertedAmount = "—"
            rateInfo = "No cached rate"
            return
        }

        let result = inputAmount * rate.rate
        convertedAmount = formatAmount(result, currency: toCurrency)
        rateInfo = "1 \(fromCurrency.rawValue) = \(String(format: "%.4f", rate.rate)) \(toCurrency.rawValue)"
        lastUpdated = rate.fetchedAt
    }

    /// Swap from/to currencies
    @MainActor
    func swapCurrencies(context: ModelContext) {
        let temp = fromCurrency
        fromCurrency = toCurrency
        toCurrency = temp
        convert(context: context)
    }

    /// Refresh rates from API
    @MainActor
    func refreshRates(context: ModelContext) async {
        isLoading = true
        errorMessage = nil

        do {
            try await service.updateCache(base: fromCurrency, context: context)
            convert(context: context)
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
            convert(context: context)
        }
    }

    private func formatAmount(_ value: Double, currency: CurrencyCode) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = currency == .JPY ? 0 : 2
        formatter.minimumFractionDigits = currency == .JPY ? 0 : 2
        formatter.groupingSeparator = " "
        return "\(currency.symbol) \(formatter.string(from: NSNumber(value: value)) ?? "—")"
    }
}
