import Foundation
import SwiftUI

struct DiscoverNewsStoryCard: View {
    let story: WikipediaService.DiscoverFeed.NewsStory
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    var showsSurface: Bool = true
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var activePageViewsTitle: String?
    @State private var isHovered = false

    private var renderedStory: AttributedString {
        let cleaned = Self.sanitizedStoryText(story.story)
        return AttributedString(cleaned)
    }

    private static func sanitizedStoryText(_ storyText: String) -> String {
        let raw = storyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        return stripMarkdownLinksPreservingLabels(in: raw)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips Markdown link wrappers (`[label](url)`) while preserving label text.
    /// Handles URLs that contain nested parentheses.
    private static func stripMarkdownLinksPreservingLabels(in text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "[" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            guard let closingBracket = text[index...].firstIndex(of: "]") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let afterBracket = text.index(after: closingBracket)
            guard afterBracket < text.endIndex, text[afterBracket] == "(" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let labelStart = text.index(after: index)
            let label = text[labelStart..<closingBracket]

            var cursor = text.index(after: afterBracket)
            var depth = 1
            while cursor < text.endIndex && depth > 0 {
                switch text[cursor] {
                case "(":
                    depth += 1
                case ")":
                    depth -= 1
                default:
                    break
                }
                cursor = text.index(after: cursor)
            }

            guard depth == 0 else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            output.append(contentsOf: label)
            index = cursor
        }

        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !story.story.isEmpty {
                Text(renderedStory)
                    .font(DiscoverTypography.storyBody)
                    .lineSpacing(1.3)
                    .lineLimit(3)
            }

            if !story.links.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(story.links.prefix(5)) { link in
                            DiscoverStoryLinkChip(
                                link: link,
                                onOpen: onOpen,
                                referenceDate: referenceDate,
                                activePageViewsTitle: $activePageViewsTitle
                            )
                        }
                    }
                    .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(12)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.04 : 0.018))
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: showsSurface ? 14 : 16, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.46 : 0.32), lineWidth: 0.7)
        }
        .discoverHoverEffect(.card, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: showsSurface ? 14 : 16, style: .continuous))
    }
}

struct DiscoverStoryLinkChip: View {
    let link: WikipediaService.SearchResult
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    @Binding var activePageViewsTitle: String?
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            onOpen(link, SystemBridge.isCommandPressed)
        } label: {
            Text(link.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(isHovered ? 0.17 : 0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(
                            Color.accentColor.opacity(isHovered ? 0.35 : 0),
                            lineWidth: 0.8
                        )
                }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .discoverHoverEffect(.chip, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contextMenu {
            ArticleQuickActionsMenuContent(
                title: link.title,
                onOpen: { onOpen(link, false) },
                onOpenInNewTab: { onOpen(link, true) },
                onShowPageViews: { activePageViewsTitle = link.title }
            )
        }
        .popover(
            isPresented: Binding(
                get: { activePageViewsTitle == link.title },
                set: { isPresented in
                    guard !isPresented else { return }
                    if activePageViewsTitle == link.title {
                        activePageViewsTitle = nil
                    }
                }
            ),
            arrowEdge: .trailing
        ) {
            if activePageViewsTitle == link.title {
                DiscoverPageViewsPopoverContent(
                    title: link.title,
                    referenceDate: referenceDate
                )
            }
        }
    }
}

struct DiscoverOnThisDayFeatureCard: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let accent: Color
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = event.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    Text(event.year)
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let article = event.article {
                        Text(article.title)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(accent.opacity(0.12), in: Capsule())
                    }
                }

                Text(event.text)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.46 : 0.32), lineWidth: 0.7)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle(pressedScale: 0.992, pressedOpacity: 0.95))
        .disabled(event.article == nil)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .discoverHoverEffect(.card, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
    }
}

struct DiscoverOnThisDayRow: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    var showsSurface: Bool = true
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = event.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(event.year)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(event.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = event.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(event.article?.title ?? event.text)
        .padding(10)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.04 : 0.018))
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.44 : 0.30), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous))
        .discoverHoverEffect(.row, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = event.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpen(article, false) },
                    onOpenInNewTab: { onOpen(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = event.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

}

struct DiscoverDidYouKnowRow: View {
    let fact: WikipediaService.DiscoverFeed.DidYouKnowFact
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    let referenceDate: Date
    var showsSurface: Bool = true
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var showingPageViewsPopover = false
    @State private var isHovered = false

    var body: some View {
        Button {
            if let article = fact.article {
                onOpen(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(fact.text)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(3)
                    if let article = fact.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(DiscoverInteractivePressStyle())
        .accessibilityLabel(fact.article?.title ?? fact.text)
        .padding(10)
        .background(
            Group {
                if showsSurface {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(isHovered ? 0.04 : 0.018))
                }
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(isHovered ? 0.44 : 0.30), lineWidth: 0.7)
        }
        .contentShape(RoundedRectangle(cornerRadius: showsSurface ? 12 : 14, style: .continuous))
        .discoverHoverEffect(.row, isActive: isHovered, reduceMotion: reduceMotion)
        .onHover { isHovered = $0 }
        .contextMenu {
            if let article = fact.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpen(article, false) },
                    onOpenInNewTab: { onOpen(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = fact.article {
                DiscoverPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

}
