import SwiftUI
import SwiftData

/// Main converter screen — flat editable list, tap any amount to type, all recalculate
struct ConverterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = ConverterViewModel()
    @State private var showAddSheet = false
    @State private var chartTarget: CurrencyCode?
    @FocusState private var focusedCurrency: CurrencyCode?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.currencies) { currency in
                        ConvertedCurrencyRow(
                            currency: currency,
                            amount: amountBinding(for: currency),
                            isFocused: focusedCurrency == currency,
                            onType: { typedCurrency, newValue in
                                viewModel.userDidType(currency: typedCurrency, value: newValue)
                            },
                            onChartTap: {
                                focusedCurrency = nil
                                chartTarget = currency
                            }
                        )
                        .focused($focusedCurrency, equals: currency)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            viewModel.removeCurrency(viewModel.currencies[index], context: modelContext)
                        }
                    }
                    .onMove { source, destination in
                        viewModel.moveCurrency(from: source, to: destination, context: modelContext)
                    }
                } header: {
                    statusHeader
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await viewModel.refreshRates(context: modelContext)
            }
            .navigationTitle("CurrencyPal")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $chartTarget) { target in
                ChartDetailView(base: chartBase(for: target), target: target)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarLeading) {
                    CrossPromoMenu()
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        focusedCurrency = nil
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(viewModel.availableCurrencies.isEmpty)
                    .accessibilityLabel(Text("Add currency"))

                    Button {
                        Task { await viewModel.refreshRates(context: modelContext) }
                    } label: {
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isLoading)
                    .accessibilityLabel(Text("Refresh rates"))
                }
                // decimalPad has no return key — without this the keyboard is a trap
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedCurrency = nil }
                        .fontWeight(.semibold)
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
            .onChange(of: focusedCurrency) {
                if let focused = focusedCurrency {
                    viewModel.userDidActivate(currency: focused)
                }
            }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await viewModel.refreshIfNeeded(context: modelContext) }
            }
        }
    }

    /// One line that answers "can I trust these numbers?"
    @ViewBuilder
    private var statusHeader: some View {
        VStack(spacing: 4) {
            if let updated = viewModel.lastUpdated {
                HStack(spacing: 4) {
                    FreshnessBadge(date: updated)
                    // The last refresh failed but we still have rates — flag it quietly.
                    if viewModel.statusMessage != nil {
                        Image(systemName: "wifi.slash")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(Text("Last refresh failed"))
                    }
                }
            } else if !viewModel.hasRates && !viewModel.isLoading {
                Label("No rates yet — pull to retry", systemImage: "wifi.slash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Only worth a second line when rates are missing entirely; with a cache
            // in hand the freshness badge already tells the story.
            if let status = viewModel.statusMessage, !viewModel.hasRates {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .textCase(nil)
        .padding(.vertical, 2)
    }

    /// A pair against itself has no history to show — quote it against the dollar
    /// (or the euro, when the dollar is the row being tapped).
    private func chartBase(for target: CurrencyCode) -> CurrencyCode {
        guard target == viewModel.activeCurrency else { return viewModel.activeCurrency }
        return target == .USD ? .EUR : .USD
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
