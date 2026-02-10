import SwiftUI
import SwiftData

/// Main converter screen — flat editable list, tap any amount to type, all recalculate
struct ConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ConverterViewModel()
    @State private var showAddSheet = false
    @State private var chartTarget: CurrencyCode?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Freshness
                if let updated = viewModel.lastUpdated {
                    FreshnessBadge(date: updated)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                }

                // Editable currency list — no NavigationLink, so TextField gets clean focus
                List {
                    ForEach(viewModel.currencies) { currency in
                        ConvertedCurrencyRow(
                            currency: currency,
                            amount: amountBinding(for: currency),
                            isActive: viewModel.activeCurrency == currency,
                            onActivate: {
                                viewModel.userDidActivate(currency: currency, context: modelContext)
                            },
                            onType: { newValue in
                                viewModel.userDidType(value: newValue, context: modelContext)
                            },
                            onChartTap: {
                                chartTarget = currency
                            }
                        )
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.removeCurrency(viewModel.currencies[index], context: modelContext)
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
            .navigationDestination(item: $chartTarget) { target in
                ChartDetailView(base: viewModel.activeCurrency, target: target)
            }
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
