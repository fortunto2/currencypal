import Foundation
import SwiftData
import Observation

/// View model for the 30-day historical chart view
@Observable
final class ChartViewModel {
    let baseCurrency: CurrencyCode
    let targetCurrency: CurrencyCode

    var dataPoints: [(date: Date, rate: Double)] = []
    var isLoading = false
    var errorMessage: String?

    var currentRate: Double? { dataPoints.last?.rate }
    var minRate: Double? { dataPoints.map(\.rate).min() }
    var maxRate: Double? { dataPoints.map(\.rate).max() }

    var percentChange: Double? {
        guard let first = dataPoints.first?.rate, let last = dataPoints.last?.rate, first > 0 else {
            return nil
        }
        return ((last - first) / first) * 100
    }

    private let service = ExchangeRateService()

    init(base: CurrencyCode, target: CurrencyCode) {
        self.baseCurrency = base
        self.targetCurrency = target
    }

    /// Load data from cache first, then refresh from API
    @MainActor
    func loadData(context: ModelContext) async {
        loadFromCache(context: context)

        isLoading = true
        errorMessage = nil

        do {
            try await service.updateHistoricalCache(
                base: baseCurrency,
                target: targetCurrency,
                days: 30,
                context: context
            )
            loadFromCache(context: context)
        } catch {
            if dataPoints.isEmpty {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    @MainActor
    private func loadFromCache(context: ModelContext) {
        let base = baseCurrency.rawValue
        let target = targetCurrency.rawValue
        let predicate = #Predicate<HistoricalRate> {
            $0.baseCurrency == base && $0.targetCurrency == target
        }
        let descriptor = FetchDescriptor<HistoricalRate>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.date)]
        )

        guard let results = try? context.fetch(descriptor), !results.isEmpty else { return }
        dataPoints = results.map { (date: $0.date, rate: $0.rate) }
    }
}
