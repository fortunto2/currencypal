import SwiftUI
import SwiftData

/// Main converter screen
struct ConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ConverterViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // From currency
                CurrencyInputCard(
                    title: "From",
                    amount: $viewModel.amount,
                    currency: $viewModel.fromCurrency,
                    isEditable: true
                )
                .onChange(of: viewModel.amount) {
                    viewModel.convert(context: modelContext)
                }
                .onChange(of: viewModel.fromCurrency) {
                    Task { await viewModel.refreshIfNeeded(context: modelContext) }
                }

                // Swap button
                Button {
                    viewModel.swapCurrencies(context: modelContext)
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.title)
                        .foregroundStyle(.accent)
                }

                // To currency
                CurrencyResultCard(
                    result: viewModel.convertedAmount,
                    currency: $viewModel.toCurrency
                )
                .onChange(of: viewModel.toCurrency) {
                    viewModel.convert(context: modelContext)
                }

                // Rate info
                if !viewModel.rateInfo.isEmpty {
                    Text(viewModel.rateInfo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                // Freshness indicator
                if let updated = viewModel.lastUpdated {
                    FreshnessBadge(date: updated)
                }

                Spacer()

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("CurrencyPal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refreshRates(context: modelContext) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                }
            }
            .task {
                await viewModel.refreshIfNeeded(context: modelContext)
            }
        }
    }
}

#Preview {
    ConverterView()
        .modelContainer(for: [ExchangeRate.self, FavoritePair.self], inMemory: true)
}
