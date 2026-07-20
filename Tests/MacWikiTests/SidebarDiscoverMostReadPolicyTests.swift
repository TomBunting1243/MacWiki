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
        #expect(selection.supportsTrendPulse)
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
        #expect(!selection.supportsTrendPulse)
    }

    @Test func emptySourcesRemainAnUnavailableMostReadSection() {
        let selection = SidebarDiscoverMostReadPolicy.selection(
            rankedItems: [],
            editorialGroups: [[], []]
        )

        #expect(selection.items.isEmpty)
        #expect(selection.contentKind == .ranked)
        #expect(selection.sectionTitle == "Most Read")
        #expect(!selection.supportsTrendPulse)
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
