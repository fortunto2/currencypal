import SwiftUI

/// Sheet listing available currencies to add to the multi-converter list
struct AddCurrencySheet: View {
    let availableCurrencies: [CurrencyCode]
    let onSelect: (CurrencyCode) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    /// Match on code or name so both "zł" hunters and "Polish" hunters find PLN.
    private var results: [CurrencyCode] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return availableCurrencies }
        return availableCurrencies.filter {
            $0.rawValue.localizedCaseInsensitiveContains(trimmed)
                || $0.name.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            List(results) { code in
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
                    .contentShape(.rect)
                }
                .tint(.primary)
                .accessibilityIdentifier("currency-\(code.rawValue)")
            }
            .searchable(text: $query, prompt: "Search currencies")
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
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
