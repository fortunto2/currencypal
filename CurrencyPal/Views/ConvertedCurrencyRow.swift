import SwiftUI

/// Each row is editable: flag + code on the left, amount TextField on the right.
/// Tapping the field makes this the active currency; all others recalculate.
struct ConvertedCurrencyRow: View {
    let currency: CurrencyCode
    @Binding var amount: String
    let isActive: Bool
    let onEdit: (String) -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(currency.flag)
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text(currency.rawValue)
                    .font(.subheadline.weight(.semibold))
                Text(currency.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 60, alignment: .leading)

            Spacer()

            Text(currency.symbol)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("0", text: $amount)
                .keyboardType(.decimalPad)
                .font(.title3.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 140)
                .focused($isFocused)
                .onChange(of: amount) {
                    if isFocused {
                        onEdit(amount)
                    }
                }
                .onChange(of: isFocused) {
                    if isFocused {
                        onEdit(amount)
                    }
                }
        }
        .padding(.vertical, 4)
        .listRowBackground(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
    }
}
