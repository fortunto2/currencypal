import SwiftUI

/// Card with currency picker and amount input
struct CurrencyInputCard: View {
    let title: String
    @Binding var amount: String
    @Binding var currency: CurrencyCode
    let isEditable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                // Currency picker
                Menu {
                    ForEach(CurrencyCode.allCases) { code in
                        Button {
                            currency = code
                        } label: {
                            Label("\(code.flag) \(code.rawValue) — \(code.name)", systemImage: currency == code ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currency.flag)
                            .font(.title2)
                        Text(currency.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }

                Spacer()

                // Amount input
                if isEditable {
                    TextField("0", text: $amount)
                        .keyboardType(.decimalPad)
                        .font(.title2.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 150)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Card displaying conversion result
struct CurrencyResultCard: View {
    let result: String
    @Binding var currency: CurrencyCode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("To")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Menu {
                    ForEach(CurrencyCode.allCases) { code in
                        Button {
                            currency = code
                        } label: {
                            Label("\(code.flag) \(code.rawValue) — \(code.name)", systemImage: currency == code ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(currency.flag)
                            .font(.title2)
                        Text(currency.rawValue)
                            .font(.headline)
                            .fontWeight(.semibold)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                    .foregroundStyle(.primary)
                }

                Spacer()

                Text(result)
                    .font(.title2.monospacedDigit())
                    .fontWeight(.medium)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
