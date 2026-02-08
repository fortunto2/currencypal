import SwiftUI
import SwiftData
import Charts

/// 30-day historical chart for a currency pair
struct ChartDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChartViewModel

    let baseCurrency: CurrencyCode
    let targetCurrency: CurrencyCode

    init(base: CurrencyCode, target: CurrencyCode) {
        self.baseCurrency = base
        self.targetCurrency = target
        self._viewModel = State(initialValue: ChartViewModel(base: base, target: target))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Chart
                if viewModel.dataPoints.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.downtrend.xyaxis",
                        description: Text(viewModel.errorMessage ?? "Historical data unavailable.")
                    )
                } else {
                    chartView
                }

                // Stats cards
                if !viewModel.dataPoints.isEmpty {
                    statsSection
                }
            }
            .padding()
        }
        .navigationTitle("\(baseCurrency.rawValue) / \(targetCurrency.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading && viewModel.dataPoints.isEmpty {
                ProgressView("Loading chart data...")
            }
        }
        .task {
            await viewModel.loadData(context: modelContext)
        }
    }

    private var chartView: some View {
        Chart(viewModel.dataPoints, id: \.date) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Rate", point.rate)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(.blue)

            AreaMark(
                x: .value("Date", point.date),
                y: .value("Rate", point.rate)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [.blue.opacity(0.2), .blue.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 240)
        .padding(.vertical)
    }

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let current = viewModel.currentRate {
                statCard(title: "Current Rate", value: String(format: "%.4f", current))
            }
            if let change = viewModel.percentChange {
                statCard(
                    title: "30d Change",
                    value: String(format: "%+.2f%%", change),
                    color: change >= 0 ? .green : .red
                )
            }
            if let low = viewModel.minRate {
                statCard(title: "30d Low", value: String(format: "%.4f", low))
            }
            if let high = viewModel.maxRate {
                statCard(title: "30d High", value: String(format: "%.4f", high))
            }
        }
    }

    private func statCard(title: String, value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
