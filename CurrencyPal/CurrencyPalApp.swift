import SwiftUI
import SwiftData

@main
struct CurrencyPalApp: App {
    private static let models: [any PersistentModel.Type] = [
        ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self
    ]

    private let container = CurrencyPalApp.makeContainer()

    var body: some Scene {
        WindowGroup {
            ConverterView()
        }
        .modelContainer(container)
    }

    /// UI tests run against a throwaway store so each case starts from the defaults.
    /// If the on-disk store is unreadable — a schema change, a corrupted file — fall
    /// back to memory rather than crashing on launch; rates re-download in seconds.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema(models)
        let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

        if !isUITesting {
            if let container = try? ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            ) {
                return container
            }
        }

        do {
            return try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Unable to create an in-memory model container: \(error)")
        }
    }
}
