import SwiftUI

/// Editable currency row.
///
/// Focusing a row clears its field and keeps the previous amount visible as the
/// placeholder. That beats trying to emulate select-all: a tap on a right-aligned
/// number puts the caret wherever it landed, so "type over the old value" would
/// splice digits into the middle of it ("0.88" + "100" → "1000.88").
/// Leaving a row untouched restores what was there.
struct ConvertedCurrencyRow: View {
    let currency: CurrencyCode
    @Binding var amount: String
    let isFocused: Bool
    let onType: (CurrencyCode, String) -> Void
    let onChartTap: () -> Void

    /// The value shown before editing began — placeholder, and fallback on exit.
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

                    Image(systemName: "chart.xyaxis.line")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(currency.name) chart"))

            Spacer(minLength: 4)

            // Right: symbol + editable amount
            Text(currency.symbol)
                .font(.caption)
                .foregroundStyle(.tertiary)

            TextField(placeholder, text: $amount)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 150)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isFocused ? Color.accentColor.opacity(0.12) : Color(.systemGray6))
                )
                .accessibilityLabel(Text("\(currency.name) amount"))
                .onChange(of: isFocused) {
                    if isFocused {
                        preEditValue = amount
                        amount = ""
                    } else if amount.isEmpty && !preEditValue.isEmpty {
                        // Tapped in, typed nothing, tapped out — put the value back.
                        amount = preEditValue
                        onType(currency, preEditValue)
                    }
                }
                .onChange(of: amount) { _, newValue in
                    guard isFocused else { return }
                    let cleaned = ConverterViewModel.sanitize(newValue)
                    if cleaned != newValue { amount = cleaned }
                    onType(currency, cleaned)
                }
        }
        .padding(.vertical, 2)
    }

    /// While editing, the old amount stays on screen greyed out.
    private var placeholder: String {
        isFocused && !preEditValue.isEmpty ? preEditValue : "0"
    }
}
