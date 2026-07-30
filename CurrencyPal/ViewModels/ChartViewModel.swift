import Foundation
import SwiftData
import Observation

/// View model for the 30-day historical chart view.
/// Shows cached points immediately, then replaces them if a fetch succeeds.
@MainActor
@Observable
final class ChartViewModel {
    let baseCurrency: CurrencyCode
    let targetCurrency: CurrencyCode

    var dataPoints: [RatePoint] = []
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

    /// Daily series only change once a day; anything fresher than this is served
    /// straight from the cache. That keeps charts instant and keeps us well under
    /// CoinGecko's keyless request budget.
    private static let historyValidFor: TimeInterval = 12 * 3600

    /// Cache first, network second — the chart is never blank when we have history.
    func loadData(context: ModelContext) async {
        loadFromCache(context: context)

        if let latest = dataPoints.last?.date, latest.timeIntervalSinceNow > -Self.historyValidFor {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let points = try await service.fetchHistory(base: baseCurrency, target: targetCurrency, days: 30)
            guard !points.isEmpty else { throw ExchangeRateError.noData }
            dataPoints = points.sorted { $0.date < $1.date }
            persist(points, context: context)
        } catch {
            if dataPoints.isEmpty {
                let failure = (error as? ExchangeRateError) ?? .from(error)
                errorMessage = failure == .noData
                    ? String(localized: "Historical data is not available for this pair.")
                    : failure.errorDescription
            }
        }

        isLoading = false
    }

    private func loadFromCache(context: ModelContext) {
        let base = baseCurrency.rawValue
        let target = targetCurrency.rawValue
        let descriptor = FetchDescriptor<HistoricalRate>(
            predicate: #Predicate<HistoricalRate> {
                $0.baseCurrency == base && $0.targetCurrency == target
            },
            sortBy: [SortDescriptor(\.date)]
        )

        guard let results = try? context.fetch(descriptor), !results.isEmpty else { return }
        dataPoints = results.map { RatePoint(date: $0.date, rate: $0.rate) }
    }

    private func persist(_ points: [RatePoint], context: ModelContext) {
        let base = baseCurrency.rawValue
        let target = targetCurrency.rawValue
        try? context.delete(model: HistoricalRate.self, where: #Predicate<HistoricalRate> {
            $0.baseCurrency == base && $0.targetCurrency == target
        })
        for point in points {
            context.insert(HistoricalRate(
                baseCurrency: base,
                targetCurrency: target,
                rate: point.rate,
                date: point.date
            ))
        }
        try? context.save()
    }
}
