import SwiftUI

/// Root view — delegates to ConverterView
struct ContentView: View {
    var body: some View {
        ConverterView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [ExchangeRate.self, FavoritePair.self], inMemory: true)
}
