import SwiftUI

struct DiscoverLongestReadEntry: Identifiable {
    let result: WikipediaService.SearchResult
    let wordCount: Int

    var id: String {
        "\(result.id)-\(result.title.lowercased().replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

struct DiscoverExpandableCollectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    let meta: String?
    let systemImage: String
    let tint: Color
    let showsLoading: Bool
    let isKeyboardFocused: Bool
    @Binding var isExpanded: Bool
    let collapsedPreviewTitles: [String]
    let content: Content
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.macWikiAccessibilityPersonalization.reduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.18)
    }

    private var hoverAnimation: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.16)
    }

    init(
        title: String,
        subtitle: String,
        meta: String? = nil,
        systemImage: String,
        tint: Color,
        showsLoading: Bool = false,
        isKeyboardFocused: Bool = false,
        isExpanded: Binding<Bool>,
        collapsedPreviewTitles: [String] = [],
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.systemImage = systemImage
        self.tint = tint
        self.showsLoading = showsLoading
        self.isKeyboardFocused = isKeyboardFocused
        self._isExpanded = isExpanded
        self.collapsedPreviewTitles = collapsedPreviewTitles
        self.content = content()
    }

    var body: some View {
        let cornerRadius: CGFloat = 18

        VStack(alignment: .leading, spacing: 0) {
            headerButton

            cardBodyContent
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .discoverSurfaceChrome(
            cornerRadius: cornerRadius,
            material: .regular,
            tintColors: collectionTintColors,
            borderColor: isKeyboardFocused ? tint : Color(nsColor: .separatorColor),
            borderOpacity: isKeyboardFocused ? 0.62 : (isHovered ? 0.48 : 0.30),
            borderWidth: isKeyboardFocused ? 1.1 : 0.7
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tint.opacity(isKeyboardFocused ? 0.80 : (isHovered ? 0.64 : 0.42)))
                .frame(width: 3)
                .padding(.vertical, 13)
        }
        .discoverHoverEffect(.card, isActive: isHovered || isKeyboardFocused, reduceMotion: reduceMotion)
        .animation(hoverAnimation, value: isKeyboardFocused)
        .animation(hoverAnimation, value: isHovered)
        .animation(expansionAnimation, value: isExpanded)
        .onHover { isHovered = $0 }
    }

    private var headerButton: some View {
        Button {
            withAnimation(expansionAnimation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                collectionIcon
                collectionTitleBlock
                Spacer(minLength: 8)
                loadingIndicator
                disclosureIndicator
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
    }

    private var collectionIcon: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.96))
            .frame(width: 34, height: 34)
            .background(
                LinearGradient(
                    colors: [
                        tint.opacity(0.94),
                        tint.opacity(colorScheme == .dark ? 0.60 : 0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .shadow(
                color: tint.opacity(
                    reduceTransparency ? 0 : (isHovered || isKeyboardFocused ? 0.22 : 0.12)
                ),
                radius: 8,
                y: 3
            )
            .symbolEffect(.bounce, value: reduceMotion ? false : isExpanded)
    }

    private var collectionTitleBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DiscoverTypography.cardTitle)
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(DiscoverTypography.cardMetadata.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let meta, !meta.isEmpty {
                Text(meta)
                    .font(DiscoverTypography.editionDate)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if showsLoading {
            AppLoadingActivityMark(
                tone: .accent,
                tint: tint,
                accessibilityLabel: "Loading \(title)"
            )
        }
    }

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isExpanded ? tint : Color.secondary.opacity(0.62))
            .frame(width: 28, height: 28)
            .discoverCircleSurfaceChrome(
                borderColor: tint,
                borderOpacity: isExpanded ? 0.26 : 0.12
            )
            .rotationEffect(.degrees(isExpanded ? 0 : -90))
            .animation(expansionAnimation, value: isExpanded)
    }

    @ViewBuilder
    private var cardBodyContent: some View {
        if isExpanded {
            expandedContent
                .padding(.top, 12)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -4)),
                        removal: .opacity.combined(with: .offset(y: -2))
                    )
                )
        } else if !collapsedPreviewTitles.isEmpty {
            collapsedPreview
                .padding(.top, 10)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -3)),
                        removal: .opacity.combined(with: .offset(y: -2))
                    )
                )
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.36))
                .frame(height: 0.7)

            VStack(alignment: .leading, spacing: 6) {
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private var collectionTintColors: [Color] {
        let isActive = isHovered || isKeyboardFocused
        return [
            tint.opacity(isActive ? 0.14 : 0.08),
            Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.035 : 0.10),
            Color.clear
        ]
    }

    private var collapsedPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(collapsedPreviewTitles.enumerated()), id: \.offset) { index, title in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(DiscoverTypography.compactRank)
                        .foregroundStyle(tint)
                        .monospacedDigit()
                        .frame(width: 18, alignment: .leading)

                    Text(title)
                        .font(DiscoverTypography.compactTitle)
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.78),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.26), lineWidth: 0.6)
                }
            }
        }
    }
}

struct DiscoverPlaylistPlaceholder: View {
    let text: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(text: String) {
        self.text = text
        actionTitle = nil
        action = nil
    }

    init(text: String, actionTitle: String, action: @escaping () -> Void) {
        self.text = text
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(text)
                .font(DiscoverTypography.cardMetadata.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(actionTitle, systemImage: "arrow.clockwise", action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct DiscoverInteractivePressStyle: ButtonStyle {
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.985
    var pressedOpacity: Double = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? pressedScale : 1))
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
    }
}

struct DiscoverPlaylistArticleRow: View {
    let result: WikipediaService.SearchResult
    let rank: Int
    let primaryStat: String
    let secondaryStat: String?
    let statTint: Color
    let isKeyboardFocused: Bool
    let onFocus: (() -> Void)?
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var rowFill: Color {
        if isKeyboardFocused {
            return statTint.opacity(colorScheme == .dark ? 0.24 : 0.17)
        }
        if isHovered {
            return Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.48 : 0.84)
        }
        return Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.36 : 0.74)
    }

    private var rowStroke: Color {
        if isKeyboardFocused {
            return statTint.opacity(0.56)
        }
        if isHovered {
            return Color(nsColor: .separatorColor).opacity(0.42)
        }
        return Color(nsColor: .separatorColor).opacity(0.20)
    }

    var body: some View {
        Button {
            onFocus?()
            onOpen(result, SystemBridge.isCommandPressed)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text("\(rank)")
                    .font(DiscoverTypography.compactRank)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)

                DiscoverThumbnailSlot(
                    thumbnailURL: result.thumbnailURL,
                    size: 46,
                    cornerRadius: 8,
                    imagePadding: 3
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(MacWikiTypography.compactRowTitle)
                        .lineLimit(2)
                    if let description = result.description, !description.isEmpty {
                        Text(description)
                            .font(MacWikiTypography.settingsHelp)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 1.5) {
                    Text(primaryStat)
                        .font(MacWikiTypography.compactStatistic)
                        .foregroundStyle(statTint)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(1)
                        .monospacedDigit()

                    if let secondaryStat, !secondaryStat.isEmpty {
                        Text(secondaryStat)
                            .font(MacWikiTypography.compactStatistic)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(1)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(rowFill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(rowStroke, lineWidth: isKeyboardFocused ? 1.05 : 0.75)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
        .discoverHoverEffect(.row, isActive: isHovered || isKeyboardFocused, reduceMotion: reduceMotion)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: isKeyboardFocused)
        .accessibilityLabel(result.title)
        .accessibilityValue(secondaryStat.map { "\(primaryStat), \($0)" } ?? primaryStat)
        .accessibilityHint("Open article. Use arrows to move focus and Return to open.")
    }
}
