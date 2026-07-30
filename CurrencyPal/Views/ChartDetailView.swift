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

    /// Currency moves are small in absolute terms — a scale anchored at zero flattens
    /// a month of movement into a straight line. Frame the data instead.
    private var yDomain: ClosedRange<Double> {
        guard let low = viewModel.minRate, let high = viewModel.maxRate,
              low.isFinite, high.isFinite, low > 0 else {
            return 0...1
        }
        guard high > low else { return (low * 0.995)...(high * 1.005) }

        let padding = (high - low) * 0.15
        return (low - padding)...(high + padding)
    }

    private var chartView: some View {
        Chart(viewModel.dataPoints, id: \.date) { point in
            AreaMark(
                x: .value("Date", point.date),
                yStart: .value("Floor", yDomain.lowerBound),
                yEnd: .value("Rate", point.rate)
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                .linearGradient(
                    colors: [.accentColor.opacity(0.28), .accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Date", point.date),
                y: .value("Rate", point.rate)
            )
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .foregroundStyle(Color.accentColor)
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let rate = value.as(Double.self) {
                        Text(Self.axisFormatter.string(from: NSNumber(value: rate)) ?? "")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { value in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .frame(height: 240)
        .padding(.vertical)
    }

    /// Rates span 0.87 (EUR) to 150 (JPY) to 64000 (BTC) — pick digits accordingly.
    private static let axisFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumSignificantDigits = 4
        return f
    }()

    private var statsSection: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            if let current = viewModel.currentRate {
                statCard(title: "Current Rate", value: rateText(current))
            }
            if let change = viewModel.percentChange {
                statCard(
                    title: "30d Change",
                    value: String(format: "%+.2f%%", change),
                    color: change >= 0 ? .green : .red
                )
            }
            if let low = viewModel.minRate {
                statCard(title: "30d Low", value: rateText(low))
            }
            if let high = viewModel.maxRate {
                statCard(title: "30d High", value: rateText(high))
            }
        }
    }

    /// A fixed "%.4f" prints 64332.6700 for BTC and 0.8787 for EUR — only one of
    /// those reads well. Significant digits handle both.
    private func rateText(_ value: Double) -> String {
        Self.axisFormatter.string(from: NSNumber(value: value)) ?? "—"
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
