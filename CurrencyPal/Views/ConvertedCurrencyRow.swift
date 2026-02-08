import SwiftUI

/// Compact row showing a converted currency result in the multi-converter list
struct ConvertedCurrencyRow: View {
    let currency: CurrencyCode
    let convertedAmount: String

    var body: some View {
        HStack {
            Text(currency.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(currency.rawValue)
                    .font(.headline)
                Text(currency.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(convertedAmount)
                .font(.body.monospacedDigit())
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }
}
