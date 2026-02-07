import SwiftUI
import SwiftData

@main
struct CurrencyPalApp: App {
    var body: some Scene {
        WindowGroup {
            ConverterView()
        }
        .modelContainer(for: [ExchangeRate.self, FavoritePair.self])
    }
}
