import SwiftUI

/// Editable currency row.
/// - Tap amount field → clears & becomes active input, all others recalculate
/// - Tap flag/name area → navigates to chart
struct ConvertedCurrencyRow: View {
    let currency: CurrencyCode
    @Binding var amount: String
    let isActive: Bool
    let onActivate: () -> Void
    let onType: (String) -> Void
    let onChartTap: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Left: flag + code + name — tap for chart
            Button(action: onChartTap) {
                HStack(spacing: 8) {
                    Text(currency.flag)
                        .font(.title2)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(currency.rawValue)
                            .font(.subheadline.weight(.semibold))
                        Text(currency.name)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Right: symbol + editable amount
            Text(currency.symbol)
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color.accentColor.opacity(0.08) : Color(.systemGray6))
                )
                .focused($isFocused)
                .onChange(of: isFocused) {
                    if isFocused && !isActive {
                        // Switching to a new row: clear old value for fresh input
                        onActivate()
                    }
                }
                .onChange(of: amount) {
                    if isFocused && isActive {
                        onType(amount)
                    }
                }
        }
        .padding(.vertical, 2)
    }
}
