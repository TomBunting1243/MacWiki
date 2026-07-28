import SwiftUI

enum ArticleListSelectionPresentation {
    case custom
    case native

    /// Native List selection owns modified clicks so macOS can add, remove, or
    /// range-select rows without the article-opening gesture fighting focus.
    func handlesPrimaryTap(
        isCommandPressed: Bool,
        isShiftPressed: Bool
    ) -> Bool {
        SavedArticleSelectionPlanner.primaryTapRouting(
            presentation: self,
            modifiers: .init(
                isCommandPressed: isCommandPressed,
                isShiftPressed: isShiftPressed,
                isOptionPressed: false
            )
        ) == .performPrimaryAction
    }
}

struct ArticleListItem<Content: View>: View {
    let accessibilityTitle: String
    let isRead: Bool
    let progress: Double
    let isCurrent: Bool
    let isSelected: Bool
    let selectionPresentation: ArticleListSelectionPresentation
    let onToggleRead: (() -> Void)?
    let onTap: () -> Void
    let label: Label?
    @ViewBuilder let content: (Bool, Label?) -> Content

    @AppStorage(AppStorageKey.Labels.displayMode) private var labelDisplayMode: LabelDisplayMode = .rowHighlight
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appearsActive) private var appearsActive

    @State private var isHovered = false

    private var rowCornerRadius: CGFloat { 8 }

    private var rowFill: Color {
        let isKeyWindow = appearsActive
        if selectionPresentation.drawsCustomSelectionChrome(isSelected: isSelected) {
            return Color(nsColor: .controlBackgroundColor)
                .opacity(colorScheme == .dark ? (isKeyWindow ? 0.24 : 0.18) : (isKeyWindow ? 0.50 : 0.40))
        }
        if isCurrent {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.05 : 0.032)
        }
        if isHovered {
            return colorScheme == .dark
                ? Color.white.opacity(isKeyWindow ? 0.060 : 0.040)
                : Color.black.opacity(isKeyWindow ? 0.032 : 0.022)
        }
        return Color.clear
    }

    private var rowStroke: Color {
        let isKeyWindow = appearsActive
        if selectionPresentation.drawsCustomSelectionChrome(isSelected: isSelected) {
            return Color.accentColor.opacity(colorScheme == .dark ? (isKeyWindow ? 0.15 : 0.11) : (isKeyWindow ? 0.12 : 0.09))
        }
        if isCurrent {
            return Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.07)
        }
        if isHovered {
            return colorScheme == .dark
                ? Color.white.opacity(isKeyWindow ? 0.10 : 0.07)
                : Color.black.opacity(isKeyWindow ? 0.055 : 0.040)
        }
        return .clear
    }

    init(
        accessibilityTitle: String,
        isRead: Bool,
        progress: Double = 0,
        isCurrent: Bool = false,
        isSelected: Bool = false,
        selectionPresentation: ArticleListSelectionPresentation = .custom,
        label: Label? = nil,
        onToggleRead: (() -> Void)? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder content: @escaping (Bool, Label?) -> Content
    ) {
        self.accessibilityTitle = accessibilityTitle
        self.isRead = isRead
        self.progress = progress
        self.isCurrent = isCurrent
        self.isSelected = isSelected
        self.selectionPresentation = selectionPresentation
        self.label = label
        self.onToggleRead = onToggleRead
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            let labelColor = label?.color.swiftUIColor
            let defaultIndicatorTint = Color.accentColor.opacity(isSelected ? 0.78 : (isCurrent ? 0.72 : 0.86))
            let indicatorTint = (labelDisplayMode == .coloredDot ? labelColor?.opacity(isSelected ? 0.72 : 0.82) : nil) ?? defaultIndicatorTint
            let defaultIndicatorTrack = Color.primary.opacity(isSelected ? 0.18 : 0.14)
            let indicatorTrack = (labelDisplayMode == .coloredDot ? labelColor?.opacity(isSelected ? 0.16 : 0.22) : nil) ?? defaultIndicatorTrack

            if let toggle = onToggleRead {
                Button(action: toggle) {
                    ReadProgressIndicator(
                        progress: progress,
                        isRead: isRead,
                        tint: indicatorTint,
                        trackColor: indicatorTrack,
                        size: 10,
                        lineWidth: 1.1
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isRead ? "Mark as unread" : "Mark as read")
                .accessibilityHidden(true)
                .help(isRead ? "Mark as unread" : "Mark as read")
                .padding(.top, 10)
                .padding(.leading, 4)
            } else {
                ReadProgressIndicator(
                    progress: progress,
                    isRead: isRead,
                    tint: indicatorTint,
                    trackColor: indicatorTrack,
                    size: 10,
                    lineWidth: 1.1
                )
                .padding(.top, 10)
                .padding(.leading, 4)
            }

            let labelToDisplay = (labelDisplayMode == .rowHighlight) ? label : nil
            content(isHovered, labelToDisplay)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(isRead ? 0.76 : 1.0)
        .background {
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill(rowFill)
                .overlay {
                    RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                        .strokeBorder(rowStroke, lineWidth: 0.75)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard selectionPresentation.handlesPrimaryTap(
                isCommandPressed: SystemBridge.isCommandPressed,
                isShiftPressed: SystemBridge.isShiftPressed
            ) else {
                return
            }
            onTap()
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            guard hovering != isHovered else { return }
            isHovered = hovering
        }
        .modifier(
            ArticleListAccessibilityModifier(
                title: accessibilityTitle,
                isRead: isRead,
                onOpen: onTap,
                onToggleRead: onToggleRead
            )
        )
    }
}

struct ArticleRow: View {
    let article: Article
    var extract: String? = nil
    var allowsEstimatedWordCount: Bool = true
    var isHovered: Bool = false
    var label: Label? = nil
    var onLabelClick: ((Label) -> Void)? = nil
    var listName: String? = nil
    var listIconName: String? = nil
    var tags: [Tag] = []
    var selectedTagId: UUID? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    private let subheadLineLimit = 2

    private var wordCountText: String? {
        ArticlePresentationFormatter.wordCountText(
            wordCount: article.wordCount,
            fallbackExtract: extract,
            allowsEstimate: allowsEstimatedWordCount
        )
    }

    private var readingTimeText: String? {
        article.wordCount.map { ArticlePresentationFormatter.readingTimeText(forWordCount: $0) }
    }

    private var hasFooterMetadata: Bool {
        wordCountText != nil || label != nil || listName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(article.title)
                .font(MacWikiTypography.articleListTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(article.description ?? " ")
                    .font(MacWikiTypography.articleListSubtitle)
                    .foregroundStyle(article.description != nil ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            Text(extract ?? " \n ")
                .font(MacWikiTypography.articleListExcerpt)
                .foregroundStyle(extract != nil ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(MacWikiTypography.articleListMetadata)
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let readingTimeText {
                        SwiftUI.Label(readingTimeText, systemImage: "clock")
                            .font(MacWikiTypography.articleListMetadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            ArticleMetadataChip(title: label.name, tint: label.color.swiftUIColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if let listName {
                        ArticleMetadataChip(
                            title: listName,
                            systemImage: listIconName ?? "folder",
                            tint: .secondary
                        )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 12, alignment: .leading)

                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            TagChipView(
                                title: tag.name,
                                isSelected: selectedTagId == tag.id,
                                showsIcon: true,
                                fixedWidth: true
                            ) {
                                onTagClick?(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, (hasFooterMetadata || !tags.isEmpty) ? 8 : 0)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ArticleRowWithFetch: View {
    let article: Article
    var hydratedMetadata: ArticleMetadataHydrationSnapshot? = nil
    var isHovered: Bool = false
    var label: Label? = nil
    var onLabelClick: ((Label) -> Void)? = nil
    var listName: String? = nil
    var listIconName: String? = nil
    var tags: [Tag] = []
    var selectedTagId: UUID? = nil
    var trendPulse: WikipediaService.TrendPulse? = nil
    var pageViewsPresentation: SidebarPageViewsPopoverConfiguration? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    private let subheadLineLimit = 2

    private var resolvedDescription: String? {
        let text = hydratedMetadata?.description ?? article.description
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private var resolvedExtract: String? {
        let text = hydratedMetadata?.extract ?? article.extract
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    private var resolvedWordCount: Int? {
        hydratedMetadata?.wordCount ?? article.wordCount
    }

    private var wordCountText: String? {
        ArticlePresentationFormatter.wordCountText(
            wordCount: resolvedWordCount,
            fallbackExtract: resolvedExtract
        )
    }

    private var readingTimeText: String? {
        resolvedWordCount.map { ArticlePresentationFormatter.readingTimeText(forWordCount: $0) }
    }

    private var displayedDescription: String { resolvedDescription ?? " " }
    private var displayedExtract: String { resolvedExtract ?? " \n " }
    private var hasDescription: Bool { resolvedDescription != nil }
    private var hasExtract: Bool { resolvedExtract != nil }
    private var hasFooterMetadata: Bool {
        wordCountText != nil || label != nil || listName != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(MacWikiTypography.articleListTitle)
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let pageViewsPresentation {
                SidebarPageViewsPopoverButton(configuration: pageViewsPresentation)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.top, 1)
                    .padding(.bottom, 1)
            } else if let trendPulse {
                SidebarTrendPulseChip(
                    pulse: trendPulse
                )
                .padding(.top, 1)
                .padding(.bottom, 1)
            }

            HStack(spacing: 6) {
                Text(displayedDescription)
                    .font(MacWikiTypography.articleListSubtitle)
                    .foregroundStyle(hasDescription ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            Text(displayedExtract)
                .font(MacWikiTypography.articleListExcerpt)
                .foregroundStyle(hasExtract ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                FlowLayout(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(MacWikiTypography.articleListMetadata)
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    if let readingTimeText {
                        SwiftUI.Label(readingTimeText, systemImage: "clock")
                            .font(MacWikiTypography.articleListMetadata)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    if let label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            ArticleMetadataChip(title: label.name, tint: label.color.swiftUIColor)
                        }
                        .buttonStyle(.plain)
                    }

                    if let listName {
                        ArticleMetadataChip(
                            title: listName,
                            systemImage: listIconName ?? "folder",
                            tint: .secondary
                        )
                    }

                }
                .frame(maxWidth: .infinity, minHeight: 12, alignment: .leading)

                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            TagChipView(
                                title: tag.name,
                                isSelected: selectedTagId == tag.id,
                                showsIcon: true,
                                fixedWidth: true
                            ) {
                                onTagClick?(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, (hasFooterMetadata || !tags.isEmpty) ? 8 : 0)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ArticleMetadataChip: View {
    let title: String
    var systemImage: String?
    var tint: Color

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }

            Text(title)
                .font(MacWikiTypography.metadataLabel)
        }
        .foregroundStyle(tint)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.8)
        }
    }
}
