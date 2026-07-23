import Testing

@testable import MacWiki

struct SidebarDiscoverMostReadPolicyTests {
    @Test func rankedItemsWinAndRetainMostReadSemantics() {
        let ranked = [result(id: "ranked", title: "Ranked Article")]
        let fallback = [result(id: "fallback", title: "Editorial Article")]

        let selection = SidebarDiscoverMostReadPolicy.selection(
            rankedItems: ranked,
            editorialGroups: [fallback]
        )

        #expect(selection.items == ranked)
        #expect(selection.contentKind == .ranked)
        #expect(selection.sectionTitle == "Most Read")
    }

    @Test func editorialFallbackPreservesPriorityAndUsesTruthfulSemantics() {
        let first = result(id: "first", title: "First Pick")
        let repeatedTitle = result(id: "repeated-title", title: "First Pick")
        let repeatedID = result(id: "first", title: "Different Title")
        let recoveredID = result(id: "repeated-title", title: "Recovered Pick")
        let second = result(id: "second", title: "Second Pick")
        let third = result(id: "third", title: "Third Pick")

        let selection = SidebarDiscoverMostReadPolicy.selection(
            rankedItems: [],
            editorialGroups: [
                [first, repeatedTitle],
                [repeatedID, recoveredID, second, third],
            ],
            limit: 2
        )

        #expect(selection.items == [first, recoveredID])
        #expect(selection.contentKind == .editorialFallback)
        #expect(selection.sectionTitle == "Discover Picks")
    }

    @Test func emptySourcesRemainAnUnavailableMostReadSection() {
        let selection = SidebarDiscoverMostReadPolicy.selection(
            rankedItems: [],
            editorialGroups: [[], []]
        )

        #expect(selection.items.isEmpty)
        #expect(selection.contentKind == .ranked)
        #expect(selection.sectionTitle == "Most Read")
    }

    @Test func nonpositiveLimitDoesNotExposeFallbackContent() {
        let selection = SidebarDiscoverMostReadPolicy.selection(
            rankedItems: [],
            editorialGroups: [[result(id: "fallback", title: "Editorial Article")]],
            limit: 0
        )

        #expect(selection.items.isEmpty)
        #expect(selection.contentKind == .ranked)
    }

    @Test func feedSelectionPrefersSelectedTimelineBeforeDefaultTimeline() {
        let selected = result(id: "selected", title: "Selected Timeline Pick")
        let defaultTimeline = result(id: "default", title: "Default Timeline Pick")

        let selection = SidebarDiscoverMostReadPolicy.selection(
            from: WikipediaService.DiscoverFeed(
                dateKey: "2026-07-20",
                dateLabel: "Stub",
                featuredArticle: nil,
                featuredImage: nil,
                newsStories: [],
                inTheNews: [],
                trending: [],
                onThisDay: [timelineEvent(id: "default-event", article: defaultTimeline)],
                onThisDaySelected: [timelineEvent(id: "selected-event", article: selected)],
                onThisDayBirths: [],
                onThisDayDeaths: [],
                holidays: [],
                didYouKnow: []
            ),
            limit: 1
        )

        #expect(selection.items == [selected])
        #expect(selection.contentKind == .editorialFallback)
    }

    @Test func editionInventoryCountsEveryUniqueArticleDestination() {
        let featured = result(id: "featured", title: "Featured")
        let trend = result(id: "trend", title: "Trending")
        let duplicateTrend = result(id: "other-id", title: "Trending")
        let story = result(id: "story", title: "Story Link")
        let inTheNews = result(id: "in-the-news", title: "In the News")
        let history = result(id: "history", title: "History")
        let born = result(id: "born", title: "Born")
        let died = result(id: "died", title: "Died")

        let feed = WikipediaService.DiscoverFeed(
            dateKey: "2026-07-20",
            dateLabel: "Stub",
            featuredArticle: featured,
            featuredImage: nil,
            newsStories: [
                .init(id: "news", story: "Stub", links: [story, duplicateTrend])
            ],
            inTheNews: [trend, inTheNews],
            trending: [trend],
            onThisDay: [],
            onThisDaySelected: [timelineEvent(id: "history-event", article: history)],
            onThisDayBirths: [timelineEvent(id: "born-event", article: born)],
            onThisDayDeaths: [timelineEvent(id: "died-event", article: died)],
            holidays: [],
            didYouKnow: []
        )

        #expect(
            SidebarDiscoverArticleInventory.articles(in: feed).map(\.title)
                == ["Featured", "Trending", "Story Link", "In the News", "History", "Born", "Died"]
        )
        #expect(
            SidebarDiscoverArticleInventory.renderedArticleRows(in: feed).map(\.title)
                == ["Featured", "Trending", "In the News"]
        )
    }

    @Test func renderedInventoryCapsPulsePreloadingToVisibleRows() {
        let featured = result(id: "featured", title: "Featured")
        let ranked = (0..<24).map { result(id: "ranked-\($0)", title: "Ranked \($0)") }
        let news = (0..<14).map { result(id: "news-\($0)", title: "News \($0)") }
        let feed = WikipediaService.DiscoverFeed(
            dateKey: "2026-07-20",
            dateLabel: "Stub",
            featuredArticle: featured,
            featuredImage: nil,
            newsStories: [],
            inTheNews: news,
            trending: ranked,
            onThisDay: [],
            onThisDaySelected: [],
            onThisDayBirths: [],
            onThisDayDeaths: [],
            holidays: [],
            didYouKnow: []
        )

        let rows = SidebarDiscoverArticleInventory.renderedArticleRows(in: feed)

        #expect(rows.count == 37)
        #expect(rows.first?.title == "Featured")
        #expect(rows.last?.title == "News 11")
        #expect(!rows.contains(where: { $0.title == "News 12" }))
    }

    @Test func manualRefreshInvalidatesPulseLoadingWithUnchangedRows() {
        let initial = SidebarDiscoverPulseLoadIdentity(
            dateKey: "2026-07-20",
            titles: ["Same Article"],
            refreshGeneration: 3
        )
        let normalizedEquivalent = SidebarDiscoverPulseLoadIdentity(
            dateKey: "2026-07-20",
            titles: ["same_article"],
            refreshGeneration: 3
        )
        let refreshed = SidebarDiscoverPulseLoadIdentity(
            dateKey: "2026-07-20",
            titles: ["Same Article"],
            refreshGeneration: 4
        )

        #expect(initial == normalizedEquivalent)
        #expect(initial != refreshed)
    }

    private func result(id: String, title: String) -> WikipediaService.SearchResult {
        WikipediaService.SearchResult(
            id: id,
            title: title,
            description: nil,
            thumbnailURL: nil
        )
    }

    private func timelineEvent(
        id: String,
        article: WikipediaService.SearchResult?
    ) -> WikipediaService.DiscoverFeed.OnThisDayEvent {
        WikipediaService.DiscoverFeed.OnThisDayEvent(
            id: id,
            year: "1843",
            text: "Stub",
            article: article
        )
    }
}
