import SwiftUI

/// Shared type and color choices, so every screen reads as one app.
enum Theme {
    /// The big number at the top of a screen.
    static func hero(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
    }

    /// Key figures in tiles and rows.
    static let metric = Font.system(.headline, design: .rounded).monospacedDigit()

    static let earnings = Color.green
    static let bonus = Color.mint
}

/// A figure with a small label under it, e.g. "$24.10/hr  True EPH".
struct MetricView: View {
    let title: String
    let value: String
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.metric)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A row of metrics; wraps to two per line at accessibility text sizes.
struct MetricRow: View {
    let metrics: [MetricView]

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .topLeading), count: typeSize.isAccessibilitySize ? 2 : metrics.count)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(metrics.indices, id: \.self) { metrics[$0] }
        }
    }
}

/// A list row whose value stands out (primary color, rounded digits) instead of the
/// default gray `LabeledContent` value.
struct ValueRow: View {
    let title: String
    let value: String
    var emphasized = false

    init(_ title: String, value: String, emphasized: Bool = false) {
        self.title = title
        self.value = value
        self.emphasized = emphasized
    }

    var body: some View {
        LabeledContent {
            Text(value)
                .font(emphasized ? Theme.metric : .body.monospacedDigit())
                .foregroundStyle(.primary)
        } label: {
            Text(title)
        }
    }
}
