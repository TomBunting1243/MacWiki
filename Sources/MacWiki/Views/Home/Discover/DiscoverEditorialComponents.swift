import SwiftUI

struct DiscoverMasthead: View {
    let dateLabel: String
    let isCompactLayout: Bool

    private var trimmedDateLabel: String {
        dateLabel.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today’s Edition")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)

                    Text("Discover")
                        .font(.system(size: isCompactLayout ? 30 : 36, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                if !trimmedDateLabel.isEmpty {
                    Text(trimmedDateLabel)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .discoverCapsuleSurfaceChrome()
                        .multilineTextAlignment(.trailing)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}

struct DiscoverSectionHeader: View {
    let title: String
    let subtitle: String

    private var normalizedSubtitle: String {
        subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var showsSubtitle: Bool {
        !normalizedSubtitle.isEmpty && normalizedSubtitle != "PLACEHOLDER"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: showsSubtitle ? 3 : 0) {
            if showsSubtitle {
                Text(normalizedSubtitle)
                    .font(DiscoverTypography.sectionSubtitle)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
            }
            Text(title)
                .font(DiscoverTypography.sectionTitle)
                .foregroundStyle(.primary)
        }
    }
}

enum DiscoverEditorialPanelTone {
    case feature
    case notebook
    case atlas
    case archive
    case timewarp

    func backgroundColors(accent: Color) -> [Color] {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return [
                Color(nsColor: .controlBackgroundColor).opacity(0.34),
                Color(nsColor: .windowBackgroundColor).opacity(0.18)
            ]
        }
    }

    var topRuleHeight: CGFloat {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp: return 0
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 16
        }
    }

    var borderOpacity: Double {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 0.08
        }
    }

    var shadowOpacity: Double {
        switch self {
        case .feature, .notebook, .atlas, .archive, .timewarp:
            return 0.04
        }
    }
}

struct DiscoverEditorialPanel<Content: View>: View {
    let accent: Color
    var tone: DiscoverEditorialPanelTone = .feature
    var contentPadding: CGFloat = 16
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color,
        tone: DiscoverEditorialPanelTone = .feature,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.tone = tone
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        let cornerRadius = tone.cornerRadius

        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: cornerRadius,
            material: .regular,
            tintColors: editorialTintColors,
            borderOpacity: 0.34,
            shadowOpacity: tone.shadowOpacity,
            shadowRadius: 8,
            shadowY: 3
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(accent.opacity(0.30))
                .frame(height: 2)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    private var editorialTintColors: [Color] {
        let accentOpacity = colorScheme == .dark ? 0.055 : 0.078
        return [
            accent.opacity(accentOpacity),
            Color(nsColor: .controlBackgroundColor).opacity(0.20),
            Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.035 : 0.10)
        ]
    }
}

struct DiscoverInsetPanel<Content: View>: View {
    let accent: Color
    var contentPadding: CGFloat = 12
    let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(
        accent: Color,
        contentPadding: CGFloat = 12,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(contentPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: 14,
            tintColors: [
                accent.opacity(colorScheme == .dark ? 0.045 : 0.07),
                Color.clear
            ],
            borderOpacity: 0.32
        )
    }
}

struct DiscoverTemporalSubsectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label(title, systemImage: systemImage)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(accent.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, 2)
        }
    }
}
