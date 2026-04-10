import SwiftUI

struct ArticleListItem<Content: View>: View {
    let isRead: Bool
    let progress: Double
    let isCurrent: Bool
    let isSelected: Bool
    let onToggleRead: (() -> Void)?
    let onTap: () -> Void
    let label: Label?
    @ViewBuilder let content: (Bool, Label?) -> Content

    @AppStorage(AppStorageKey.Labels.displayMode) private var labelDisplayMode: LabelDisplayMode = .rowHighlight
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var isHovered = false

    private var rowCornerRadius: CGFloat { 8 }

    private var rowFill: Color {
        let isKeyWindow = controlActiveState == .key
        if isSelected {
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
        let isKeyWindow = controlActiveState == .key
        if isSelected {
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
        isRead: Bool,
        progress: Double = 0,
        isCurrent: Bool = false,
        isSelected: Bool = false,
        label: Label? = nil,
        onToggleRead: (() -> Void)? = nil,
        onTap: @escaping () -> Void,
        @ViewBuilder content: @escaping (Bool, Label?) -> Content
    ) {
        self.isRead = isRead
        self.progress = progress
        self.isCurrent = isCurrent
        self.isSelected = isSelected
        self.label = label
        self.onToggleRead = onToggleRead
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        Button(action: onTap) {
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
                            trackColor: indicatorTrack
                        )
                        .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(isRead ? "Mark as unread" : "Mark as read")
                    .padding(.top, 10)
                    .padding(.leading, 4)
                } else {
                    ReadProgressIndicator(
                        progress: progress,
                        isRead: isRead,
                        tint: indicatorTint,
                        trackColor: indicatorTrack
                    )
                    .frame(width: 8, height: 8)
                    .padding(.top, 10)
                    .padding(.leading, 4)
                }

                let labelToDisplay = (labelDisplayMode == .rowHighlight) ? label : nil
                content(isHovered, labelToDisplay)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
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
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            guard hovering != isHovered else { return }
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open article")
    }
}

struct ArticleRow: View {
    let article: Article
    var extract: String? = nil
    var allowsEstimatedWordCount: Bool = true
    var isHovered: Bool = false
    var label: Label? = nil
    var onLabelClick: ((Label) -> Void)? = nil
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

    private var hasFooterMetadata: Bool {
        wordCountText != nil || label != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(article.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(article.description ?? " ")
                    .font(.subheadline)
                    .foregroundStyle(article.description != nil ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            Text(extract ?? " \n ")
                .font(.subheadline)
                .foregroundStyle(extract != nil ? AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(.caption)
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)))

                    if let label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(label.color.swiftUIColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(label.color.swiftUIColor.opacity(0.08), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(label.color.swiftUIColor.opacity(0.18), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 12, alignment: .leading)

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
    var tags: [Tag] = []
    var selectedTagId: UUID? = nil
    var trendPulse: WikipediaService.TrendPulse? = nil
    var onTrendPulseTap: ((WikipediaService.TrendPulse) -> Void)? = nil
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

    private var displayedDescription: String { resolvedDescription ?? " " }
    private var displayedExtract: String { resolvedExtract ?? " \n " }
    private var hasDescription: Bool { resolvedDescription != nil }
    private var hasExtract: Bool { resolvedExtract != nil }
    private var hasFooterMetadata: Bool { wordCountText != nil || label != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(article.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let trendPulse {
                SidebarTrendPulseChip(
                    pulse: trendPulse,
                    onChartRequested: {
                        onTrendPulseTap?(trendPulse)
                    }
                )
                .padding(.top, 1)
                .padding(.bottom, 1)
            }

            HStack(spacing: 6) {
                Text(displayedDescription)
                    .font(.subheadline)
                    .foregroundStyle(hasDescription ? AnyShapeStyle(Color(nsColor: .secondaryLabelColor)) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            Text(displayedExtract)
                .font(.subheadline)
                .foregroundStyle(hasExtract ? AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(.caption)
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)))

                    if let label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(label.color.swiftUIColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(label.color.swiftUIColor.opacity(0.08), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(label.color.swiftUIColor.opacity(0.18), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 12, alignment: .leading)

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
