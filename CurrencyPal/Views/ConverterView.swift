import SwiftUI
import SwiftData

/// Main converter screen — flat list, tap any row to type, all others recalculate
struct ConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ConverterViewModel()
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Freshness indicator
                if let updated = viewModel.lastUpdated {
                    FreshnessBadge(date: updated)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                // Currency list — every row is editable
                List {
                    ForEach(viewModel.currencies) { currency in
                        NavigationLink {
                            ChartDetailView(base: viewModel.activeCurrency, target: currency)
                        } label: {
                            ConvertedCurrencyRow(
                                currency: currency,
                                amount: amountBinding(for: currency),
                                isActive: viewModel.activeCurrency == currency,
                                onEdit: { newValue in
                                    viewModel.userDidEditAmount(
                                        for: currency,
                                        newValue: newValue,
                                        context: modelContext
                                    )
                                }
                            )
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let code = viewModel.currencies[index]
                            viewModel.removeCurrency(code, context: modelContext)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveCurrency(from: source, to: destination, context: modelContext)
                    }
                }
                .listStyle(.plain)

                // Error
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }
            }
            .navigationTitle("CurrencyPal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.availableCurrencies.isEmpty)

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
            .sheet(isPresented: $showAddSheet) {
                AddCurrencySheet(
                    availableCurrencies: viewModel.availableCurrencies
                ) { code in
                    viewModel.addCurrency(code, context: modelContext)
                }
            }
            .task {
                viewModel.loadCurrencies(context: modelContext)
                await viewModel.refreshIfNeeded(context: modelContext)
            }
        }
    }

    /// Two-way binding into viewModel.amounts for a given currency
    private func amountBinding(for currency: CurrencyCode) -> Binding<String> {
        Binding(
            get: { viewModel.amounts[currency] ?? "" },
            set: { viewModel.amounts[currency] = $0 }
        )
    }
}

#Preview {
    ConverterView()
        .modelContainer(for: [ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self], inMemory: true)
}
