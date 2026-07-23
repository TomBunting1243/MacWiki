import SwiftUI

struct SidebarDiscoverStatsButton: View {
    let title: String
    let referenceDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        SidebarPageViewsPopoverButton(
            configuration: SidebarPageViewsPopoverConfiguration(
                title: title,
                referenceDate: referenceDate,
                initialPulse: nil,
                style: .iconOnly,
                isPresented: $isPresented,
                onRequestPresentation: {
                    isPresented = true
                }
            )
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct SidebarDiscoverSectionHeader: View {
    let title: LocalizedStringResource
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)

            Spacer(minLength: 4)

            Text(count.formatted())
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
                .accessibilityLabel("\(count) items")
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

struct DiscoverTimelineRow: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void

    @State private var showingPageViewsPopover = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                if let article = event.article {
                    onOpenArticle(article, SystemBridge.isCommandPressed)
                }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let article = event.article {
                SidebarDiscoverStatsButton(
                    title: article.title,
                    referenceDate: referenceDate,
                    isPresented: $showingPageViewsPopover
                )
            }
        }
        .sidebarDiscoverInteractiveHover(isEnabled: event.article != nil)
        .disabled(event.article == nil)
        .contextMenu {
            if let article = event.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpenArticle(article, false) },
                    onOpenInNewTab: { onOpenArticle(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .discoverContentRowSpacing()
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.year)
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(MacWikiTypography.compactRowBody)
                    .lineSpacing(2)
                    .lineLimit(3)
                if let article = event.article {
                    Text(article.title)
                        .font(MacWikiTypography.compactRowMetadata)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct DiscoverFactRow: View {
    let fact: WikipediaService.DiscoverFeed.DidYouKnowFact
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void

    @State private var showingPageViewsPopover = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                if let article = fact.article {
                    onOpenArticle(article, SystemBridge.isCommandPressed)
                }
            } label: {
                factContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let article = fact.article {
                SidebarDiscoverStatsButton(
                    title: article.title,
                    referenceDate: referenceDate,
                    isPresented: $showingPageViewsPopover
                )
            }
        }
        .sidebarDiscoverInteractiveHover(isEnabled: fact.article != nil)
        .disabled(fact.article == nil)
        .contextMenu {
            if let article = fact.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpenArticle(article, false) },
                    onOpenInNewTab: { onOpenArticle(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .discoverContentRowSpacing()
    }

    private var factContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb")
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(fact.text)
                    .font(MacWikiTypography.compactRowBody)
                    .lineSpacing(2)
                    .lineLimit(3)
                if let article = fact.article {
                    Text(article.title)
                        .font(MacWikiTypography.compactRowMetadata)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

struct DiscoverStoryRow: View {
    let story: WikipediaService.DiscoverFeed.NewsStory
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void

    @State private var activePageViewsTitle: String?

    private var renderedStoryText: String {
        Self.sanitizedStoryText(story.story)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !story.story.isEmpty {
                Text(renderedStoryText)
                    .font(MacWikiTypography.compactRowBody)
                    .lineSpacing(2)
                    .lineLimit(3)
            }

            if !story.links.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(story.links.prefix(4)) { article in
                        HStack(spacing: 2) {
                            Button {
                                onOpenArticle(article, SystemBridge.isCommandPressed)
                            } label: {
                                Text(article.title)
                                    .font(MacWikiTypography.compactRowMetadata)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)

                            SidebarDiscoverStatsButton(
                                title: article.title,
                                referenceDate: referenceDate,
                                isPresented: Binding(
                                    get: { activePageViewsTitle == article.title },
                                    set: { isPresented in
                                        activePageViewsTitle = isPresented ? article.title : nil
                                    }
                                )
                            )
                        }
                        .padding(.leading, 8)
                        .padding(.trailing, 4)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .sidebarDiscoverInteractiveHover()
                        .contextMenu {
                            ArticleQuickActionsMenuContent(
                                title: article.title,
                                onOpen: { onOpenArticle(article, false) },
                                onOpenInNewTab: { onOpenArticle(article, true) },
                                onShowPageViews: { activePageViewsTitle = article.title }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .discoverContentRowSpacing()
    }

    private static func sanitizedStoryText(_ storyText: String) -> String {
        let raw = storyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        return stripMarkdownLinksPreservingLabels(in: raw)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
}

struct DiscoverHolidayListRow: View {
    let holiday: WikipediaService.DiscoverFeed.HolidayItem
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void

    @State private var showingPageViewsPopover = false

    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Button {
                if let article = holiday.article {
                    onOpenArticle(article, SystemBridge.isCommandPressed)
                }
            } label: {
                rowContent
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let article = holiday.article {
                SidebarDiscoverStatsButton(
                    title: article.title,
                    referenceDate: referenceDate,
                    isPresented: $showingPageViewsPopover
                )
            }
        }
        .sidebarDiscoverInteractiveHover(isEnabled: holiday.article != nil)
        .disabled(holiday.article == nil)
        .contextMenu {
            if let article = holiday.article {
                ArticleQuickActionsMenuContent(
                    title: article.title,
                    onOpen: { onOpenArticle(article, false) },
                    onOpenInNewTab: { onOpenArticle(article, true) },
                    onShowPageViews: { showingPageViewsPopover = true }
                )
            }
        }
        .discoverContentRowSpacing()
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar")
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.text)
                    .font(MacWikiTypography.compactRowBody)
                    .lineSpacing(2)
                    .lineLimit(3)
                if let article = holiday.article {
                    Text(article.title)
                        .font(MacWikiTypography.compactRowMetadata)
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    func discoverContentRowSpacing() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
    }

    func sidebarDiscoverInteractiveHover(isEnabled: Bool = true) -> some View {
        modifier(SidebarDiscoverInteractiveHoverModifier(isEnabled: isEnabled))
    }
}

private struct SidebarDiscoverInteractiveHoverModifier: ViewModifier {
    let isEnabled: Bool
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovered ? 0.085 : 0))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = isEnabled && hovering
            }
    }
}
