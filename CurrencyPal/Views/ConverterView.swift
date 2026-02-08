import SwiftUI
import SwiftData

/// Main converter screen with multi-currency list
struct ConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ConverterViewModel()
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Base currency + amount header
                CurrencyInputCard(
                    title: "Base Currency",
                    amount: $viewModel.amount,
                    currency: $viewModel.fromCurrency,
                    isEditable: true
                )
                .padding()
                .onChange(of: viewModel.amount) {
                    viewModel.convertAll(context: modelContext)
                }
                .onChange(of: viewModel.fromCurrency) {
                    Task { await viewModel.refreshIfNeeded(context: modelContext) }
                }

                // Freshness indicator
                if let updated = viewModel.lastUpdated {
                    FreshnessBadge(date: updated)
                        .padding(.bottom, 8)
                }

                // Target currencies list
                List {
                    ForEach(viewModel.selectedTargets) { target in
                        NavigationLink {
                            ChartDetailView(base: viewModel.fromCurrency, target: target)
                        } label: {
                            ConvertedCurrencyRow(
                                currency: target,
                                convertedAmount: viewModel.convertedAmounts[target] ?? "—"
                            )
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let code = viewModel.selectedTargets[index]
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
                viewModel.loadSelectedCurrencies(context: modelContext)
                await viewModel.refreshIfNeeded(context: modelContext)
            }
        }
    }
}

#Preview {
    ConverterView()
        .modelContainer(for: [ExchangeRate.self, SelectedCurrency.self, HistoricalRate.self], inMemory: true)
}
