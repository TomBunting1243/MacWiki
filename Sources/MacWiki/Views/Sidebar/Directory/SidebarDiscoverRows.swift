import SwiftUI

struct DiscoverTimelineRow: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void

    @State private var showingPageViewsPopover = false

    var body: some View {
        Button {
            if let article = event.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
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
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = event.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
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
        Button {
            if let article = fact.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
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
        .buttonStyle(.plain)
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
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = fact.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
        .discoverContentRowSpacing()
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
                        Button {
                            onOpenArticle(article, SystemBridge.isCommandPressed)
                        } label: {
                            Text(article.title)
                                .font(MacWikiTypography.compactRowMetadata)
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            ArticleQuickActionsMenuContent(
                                title: article.title,
                                onOpen: { onOpenArticle(article, false) },
                                onOpenInNewTab: { onOpenArticle(article, true) },
                                onShowPageViews: { activePageViewsTitle = article.title }
                            )
                        }
                        .popover(
                            isPresented: Binding(
                                get: { activePageViewsTitle == article.title },
                                set: { isPresented in
                                    guard !isPresented else { return }
                                    if activePageViewsTitle == article.title {
                                        activePageViewsTitle = nil
                                    }
                                }
                            ),
                            arrowEdge: .trailing
                        ) {
                            if activePageViewsTitle == article.title {
                                SidebarPageViewsPopoverContent(
                                    title: article.title,
                                    referenceDate: referenceDate
                                )
                            }
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
        Button {
            if let article = holiday.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
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
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = holiday.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
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
}
