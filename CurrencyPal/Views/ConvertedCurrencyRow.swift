import SwiftUI

/// Editable currency row with "select-all" behavior:
/// - Tap amount → highlights row, value stays visible
/// - Start typing → old value replaced with new input (like select-all + type)
/// - Tap flag/name → navigates to chart
struct ConvertedCurrencyRow: View {
    let currency: CurrencyCode
    @Binding var amount: String
    let isActive: Bool
    let onActivate: () -> Void
    let onType: (String) -> Void
    let onChartTap: () -> Void

    @FocusState private var isFocused: Bool
    /// When true, the next additive keystroke replaces the entire value
    @State private var pendingReplace = false
    @State private var preEditValue = ""

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
                        .fill(isFocused ? Color.accentColor.opacity(0.1) : Color(.systemGray6))
                )
                .focused($isFocused)
                .onChange(of: isFocused) {
                    if isFocused && !isActive {
                        // Tapped a new row — mark for replacement, keep value visible
                        pendingReplace = true
                        preEditValue = amount
                        onActivate()
                    }
                }
                .onChange(of: amount) {
                    guard isFocused else { return }

                    if pendingReplace {
                        pendingReplace = false
                        // First keystroke after focus: replace old value
                        if amount.count > preEditValue.count {
                            // User typed a character — keep only the new part
                            let typed = String(amount.suffix(amount.count - preEditValue.count))
                            amount = typed
                        }
                        // If backspace: amount is shorter, just use as-is
                        onType(amount)
                    } else if isActive {
                        onType(amount)
                    }
                }
        }
        .padding(.vertical, 2)
    }
}
