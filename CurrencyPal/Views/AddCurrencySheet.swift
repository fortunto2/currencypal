import SwiftUI

/// Sheet listing available currencies to add to the multi-converter list
struct AddCurrencySheet: View {
    let availableCurrencies: [CurrencyCode]
    let onSelect: (CurrencyCode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(availableCurrencies) { code in
                Button {
                    onSelect(code)
                    dismiss()
                } label: {
                    HStack {
                        Text(code.flag)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(code.rawValue)
                                .font(.headline)
                            Text(code.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(code.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.primary)
            }
            .navigationTitle("Add Currency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
