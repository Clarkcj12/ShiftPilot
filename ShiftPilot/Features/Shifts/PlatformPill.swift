import SwiftUI

extension GigPlatform {
    var color: Color {
        switch self {
        case .doorDash: .red
        case .uber: .primary
        case .uberEats: .green
        case .lyft: .pink
        case .instacart: .orange
        case .grubhub: .brown
        case .shipt: .teal
        case .spark: .blue
        case .amazonFlex: .indigo
        case .other: .gray
        }
    }
}

struct PlatformPill: View {
    let platform: GigPlatform
    var isSelected = true

    var body: some View {
        Text(platform.name)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(isSelected ? platform.color : .secondary)
            .background(platform.color.opacity(isSelected ? 0.18 : 0.06), in: Capsule())
            .overlay {
                Capsule().strokeBorder(isSelected ? platform.color.opacity(0.6) : .clear)
            }
    }
}

/// The distinct platforms that paid during a shift, in a stable order.
struct PlatformPills: View {
    let platforms: Set<GigPlatform>
    var limit = 3

    var body: some View {
        let ordered = GigPlatform.allCases.filter(platforms.contains)
        HStack(spacing: 4) {
            ForEach(ordered.prefix(limit)) { PlatformPill(platform: $0) }
            if ordered.count > limit {
                Text("+\(ordered.count - limit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct PlatformPicker: View {
    @Binding var selection: GigPlatform

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
            ForEach(GigPlatform.allCases) { platform in
                Button {
                    selection = platform
                } label: {
                    PlatformPill(platform: platform, isSelected: platform == selection)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(platform == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
