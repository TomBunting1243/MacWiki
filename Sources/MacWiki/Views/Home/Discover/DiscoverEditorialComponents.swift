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
                        .font(DiscoverTypography.editorialKicker)
                        .textCase(.uppercase)
                        .foregroundStyle(.tertiary)

                    Text("Discover")
                        .font(DiscoverTypography.mastheadTitle(isCompact: isCompactLayout))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 8)

                if !trimmedDateLabel.isEmpty {
                    Text(trimmedDateLabel)
                        .font(DiscoverTypography.editionDate)
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

struct DiscoverEditorialPanel<Content: View>: View {
    let accent: Color
    var contentPadding: CGFloat = 16
    let content: Content

    init(
        accent: Color,
        contentPadding: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.accent = accent
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, contentPadding)
            .padding(.top, max(8, contentPadding * 0.55))
            .padding(.bottom, max(3, contentPadding * 0.25))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(accent.opacity(0.28))
                    .frame(height: 1)
            }
    }
}

struct DiscoverInsetPanel<Content: View>: View {
    let accent: Color
    var contentPadding: CGFloat = 12
    let content: Content

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
        content
            .padding(.leading, contentPadding)
            .padding(.trailing, max(4, contentPadding * 0.5))
            .padding(.vertical, max(4, contentPadding * 0.35))
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(accent.opacity(0.34))
                    .frame(width: 2)
            }
    }
}

struct DiscoverTemporalSubsectionHeader: View {
    let title: String
    let systemImage: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label(title, systemImage: systemImage)
                .font(DiscoverTypography.controlAuxiliary)
                .foregroundStyle(.secondary)

            Rectangle()
                .fill(accent.opacity(0.18))
                .frame(height: 1)
                .padding(.leading, 2)
        }
    }
}
