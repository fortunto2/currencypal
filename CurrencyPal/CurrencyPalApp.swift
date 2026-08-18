import SwiftUI
import SwiftData
import SuperDuperAnalytics

@main
struct CurrencyPalApp: App {
    private static let models: [any PersistentModel.Type] = [
        ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self
    ]

    private let container = CurrencyPalApp.makeContainer()

    /// App Store Connect counts downloads; nothing there counts a second launch. This does.
    /// The source id is registered in superduper-analytics — ingest rejects unknown ones, so a
    /// typo shows up as silence rather than as data landing in another product's bucket.
    ///
    /// UI test runs are excluded: a screenshot pass launches the app dozens of times and would
    /// otherwise invent users who do not exist.
    init() {
        guard !ProcessInfo.processInfo.arguments.contains("-uiTesting") else { return }
        Analytics.configure(source: "currencypal")
        Analytics.track("app_launched")
    }

    var body: some Scene {
        WindowGroup {
            ConverterView()
        }
        .modelContainer(container)
        // The buffer dies with the process, and a converter is the kind of app someone opens for
        // four seconds at a till. Without this, most launches would never be sent.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Analytics.flush() }
        }
    }

    @Environment(\.scenePhase) private var scenePhase

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
