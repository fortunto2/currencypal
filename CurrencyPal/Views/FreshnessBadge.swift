import SwiftUI

/// Shows when rates were last updated, with visual staleness indicator
struct FreshnessBadge: View {
    let date: Date

    private var isStale: Bool {
        date.timeIntervalSinceNow < -4 * 3600
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isStale ? .orange : .green)
                .frame(width: 6, height: 6)
            Text("Rates from \(timeAgo)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
    }
}
