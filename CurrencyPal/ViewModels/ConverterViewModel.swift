import Foundation
import SwiftData
import Observation

/// Multi-currency converter. Any row is editable — all others recalculate instantly.
///
/// Rates live in memory as "1 USD = X target" and are only refreshed from the
/// network. Conversion never touches SwiftData, so typing stays smooth no matter
/// how many currencies are on screen.
@MainActor
@Observable
final class ConverterViewModel {
    var activeCurrency: CurrencyCode = .USD
    var amounts: [CurrencyCode: String] = [:]
    var currencies: [CurrencyCode] = []
    var lastUpdated: Date?
    var isLoading = false
    /// Non-blocking note about the last refresh (offline, server down…).
    var statusMessage: String?
    /// True once we know there is nothing to convert with.
    var hasRates: Bool { usdRates.count > 1 }

    /// "1 USD = value <code>" — the pivot every conversion goes through.
    private var usdRates: [CurrencyCode: Double] = [:]
    private let service = ExchangeRateService()

    private static let defaultCurrencies: [CurrencyCode] = [.USD, .EUR, .GBP, .JPY, .RUB, .BTC]

    /// Rates older than this are refreshed on appear.
    private static let staleAfter: TimeInterval = 4 * 3600

    // MARK: - Lifecycle

    func loadCurrencies(context: ModelContext) {
        let descriptor = FetchDescriptor<SelectedCurrency>(sortBy: [SortDescriptor(\.sortOrder)])
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

        if currencies.isEmpty { currencies = Self.defaultCurrencies }
        if !currencies.contains(activeCurrency) {
            activeCurrency = currencies.first ?? .USD
        }
        if amounts[activeCurrency] == nil {
            amounts[activeCurrency] = "1"
        }
    }

    /// Pull cached rates into memory. Runs before any network call so the app is
    /// usable offline from the first frame.
    func loadCachedRates(context: ModelContext) {
        let usd = CurrencyCode.USD.rawValue
        let descriptor = FetchDescriptor<ExchangeRate>(
            predicate: #Predicate<ExchangeRate> { $0.baseCurrency == usd }
        )
        let rows = (try? context.fetch(descriptor)) ?? []

        var map: [CurrencyCode: Double] = [:]
        var oldest: Date?
        for row in rows {
            guard let code = CurrencyCode(rawValue: row.targetCurrency), row.rate > 0 else { continue }
            map[code] = row.rate
            if oldest == nil || row.fetchedAt < oldest! { oldest = row.fetchedAt }
        }

        setRates(map, fetchedAt: oldest)
    }

    /// Replace the in-memory pivot table and refresh every row.
    func setRates(_ rates: [CurrencyCode: Double], fetchedAt: Date?) {
        var map = rates.filter { $0.value > 0 }
        map[.USD] = 1.0
        usdRates = map
        lastUpdated = fetchedAt
        recalculate()
    }

    // MARK: - User Input

    /// User tapped a row — make it active, keep the value visible.
    func userDidActivate(currency: CurrencyCode) {
        guard activeCurrency != currency else { return }
        activeCurrency = currency
    }

    /// User typed a value in the active row.
    func userDidType(value: String) {
        amounts[activeCurrency] = value
        recalculate()
    }

    /// User typed in a specific row. Passing the currency explicitly avoids any
    /// ordering dependency between the focus change and the first keystroke.
    func userDidType(currency: CurrencyCode, value: String) {
        activeCurrency = currency
        amounts[currency] = value
        recalculate()
    }

    /// Cross-calculate every row from the active one, pivoting through USD.
    /// If active is EUR and 1 USD = 0.92 EUR = 149.85 JPY,
    /// then 1 EUR = 149.85 / 0.92 = 162.88 JPY.
    func recalculate() {
        let raw = amounts[activeCurrency] ?? ""
        // Accept either separator: the decimal keypad shows whichever the locale uses.
        let normalized = raw.replacingOccurrences(of: ",", with: ".")

        guard !normalized.isEmpty, let inputAmount = Double(normalized), inputAmount.isFinite else {
            for code in currencies where code != activeCurrency {
                amounts[code] = ""
            }
            return
        }

        guard let activeRate = usdRates[activeCurrency], activeRate > 0 else {
            for code in currencies where code != activeCurrency {
                amounts[code] = "—"
            }
            return
        }

        for target in currencies where target != activeCurrency {
            if let targetRate = usdRates[target], targetRate > 0 {
                amounts[target] = Self.format(inputAmount * (targetRate / activeRate), currency: target)
            } else {
                amounts[target] = "—"
            }
        }
    }

    // MARK: - List Management

    func addCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard !currencies.contains(code) else { return }
        currencies.append(code)
        context.insert(SelectedCurrency(currencyCode: code.rawValue, sortOrder: currencies.count - 1))
        try? context.save()
        recalculate()
    }

    func removeCurrency(_ code: CurrencyCode, context: ModelContext) {
        guard currencies.count > 2 else { return }
        currencies.removeAll { $0 == code }
        amounts.removeValue(forKey: code)
        if activeCurrency == code {
            activeCurrency = currencies.first ?? .USD
            if amounts[activeCurrency]?.isEmpty ?? true { amounts[activeCurrency] = "1" }
        }
        reindexSortOrders(context: context)
        recalculate()
    }

    func moveCurrency(from source: IndexSet, to destination: Int, context: ModelContext) {
        currencies.move(fromOffsets: source, toOffset: destination)
        reindexSortOrders(context: context)
    }

    var availableCurrencies: [CurrencyCode] {
        CurrencyCode.allCases.filter { !currencies.contains($0) }
    }

    // MARK: - Network

    /// Fetch a fresh USD snapshot. The cache is only replaced once the fetch
    /// succeeds — a failed refresh leaves the previous rates intact.
    func refreshRates(context: ModelContext) async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = nil

        do {
            let snapshot = try await service.fetchUSDSnapshot()
            apply(snapshot, context: context)
        } catch {
            let failure = (error as? ExchangeRateError) ?? .from(error)
            // Nothing cached yet — say so; otherwise keep converting with what we have.
            statusMessage = hasRates ? failure.errorDescription : ExchangeRateError.noData.errorDescription
            recalculate()
        }

        isLoading = false
    }

    /// Refresh only if the cached rates are missing or stale.
    func refreshIfNeeded(context: ModelContext) async {
        loadCachedRates(context: context)

        let isStale = lastUpdated.map { $0.timeIntervalSinceNow < -Self.staleAfter } ?? true
        if !hasRates || isStale {
            await refreshRates(context: context)
        }
    }

    // MARK: - Private

    /// Replace the cached rates with a freshly fetched snapshot.
    private func apply(_ snapshot: RateSnapshot, context: ModelContext) {
        var map: [CurrencyCode: Double] = [:]
        for (rawCode, rate) in snapshot.rates {
            guard let code = CurrencyCode(rawValue: rawCode), rate > 0 else { continue }
            map[code] = rate
        }

        setRates(map, fetchedAt: snapshot.fetchedAt)
        statusMessage = nil

        // Persist last: the UI is already correct even if the write fails.
        try? context.delete(model: ExchangeRate.self)
        for (code, rate) in usdRates {
            context.insert(ExchangeRate(
                baseCurrency: CurrencyCode.USD.rawValue,
                targetCurrency: code.rawValue,
                rate: rate,
                fetchedAt: snapshot.fetchedAt
            ))
        }
        try? context.save()
    }

    private func reindexSortOrders(context: ModelContext) {
        try? context.delete(model: SelectedCurrency.self)
        for (index, code) in currencies.enumerated() {
            context.insert(SelectedCurrency(currencyCode: code.rawValue, sortOrder: index))
        }
        try? context.save()
    }

    // MARK: - Formatting

    /// The separator this build displays and expects — the locale's, so a German
    /// user sees "1234,56" and the keypad's comma key produces something valid.
    static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    private static let decimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        // No grouping: the value has to stay round-trippable through a text field.
        f.groupingSeparator = ""
        f.usesGroupingSeparator = false
        f.minimumFractionDigits = 0
        // Default is bankers' rounding; people expect .5 to go up on a money screen.
        f.roundingMode = .halfUp
        return f
    }()

    /// Format a converted amount for display in an editable field:
    /// no grouping separators, plain "." decimals, precision suited to the currency.
    static func format(_ value: Double, currency: CurrencyCode) -> String {
        guard value.isFinite else { return "—" }

        if currency.isCrypto {
            // Crypto amounts span many orders of magnitude — keep significant digits,
            // not a fixed number of decimals.
            let magnitude = abs(value)
            let digits: Int
            switch magnitude {
            case 0: digits = 2
            case ..<0.0001: digits = 8
            case ..<1: digits = 6
            case ..<1000: digits = 4
            default: digits = 2
            }
            decimalFormatter.maximumFractionDigits = digits
            return decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
        }

        // Zero-decimal currencies: yen and won are not quoted in fractions.
        decimalFormatter.maximumFractionDigits = (currency == .JPY || currency == .KRW) ? 0 : 2
        return decimalFormatter.string(from: NSNumber(value: value)) ?? "0"
    }

    /// Keep only what a decimal amount may contain — guards against pasted text.
    /// Either separator is accepted on input and normalised to the locale's.
    static func sanitize(_ input: String) -> String {
        let separator = decimalSeparator
        var result = ""
        var seenSeparator = false
        for character in input {
            if character.isNumber {
                result.append(character)
            } else if (character == "." || character == ",") && !seenSeparator {
                seenSeparator = true
                result.append(separator)
            }
        }
        return result
    }
}
