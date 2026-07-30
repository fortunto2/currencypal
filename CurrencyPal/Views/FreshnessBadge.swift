import SwiftUI

/// Shows when rates were last updated, with a visual staleness indicator.
struct FreshnessBadge: View {
    let date: Date

    private static let staleAfter: TimeInterval = 4 * 3600

    private var age: TimeInterval { -date.timeIntervalSinceNow }

    private var isStale: Bool { age > Self.staleAfter }

    /// A just-fetched rate must not read "in 0 sec", which is what
    /// RelativeDateTimeFormatter produces for a timestamp at (or a hair past) now.
    private var label: String {
        guard age >= 60 else { return String(localized: "Updated just now") }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: .now)
        return String(localized: "Updated \(relative)")
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isStale ? .orange : .green)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(isStale ? "Rates may be out of date. \(label)" : label))
    }
}
