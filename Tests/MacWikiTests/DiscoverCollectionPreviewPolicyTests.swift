import Testing

@testable import MacWiki

@MainActor
struct DiscoverCollectionPreviewPolicyTests {
    @Test func editorialPreviewUsesExistingFeedPriorityAndDeduplicatesTitles() {
        let featured = result(id: "featured", title: "Ada Lovelace")
        let items = DiscoverCollectionPreviewPolicy.editorialItems(
            featured: featured,
            todayMostRead: [
                result(id: "duplicate", title: "Ada_Lovelace"),
                result(id: "today", title: "Grace Hopper")
            ],
            inTheNews: [result(id: "news", title: "Katherine Johnson")],
            trending: [result(id: "trend", title: "Margaret Hamilton")],
            limit: 3
        )

        #expect(items.map(\.title) == ["Ada Lovelace", "Grace Hopper", "Katherine Johnson"])
    }

    @Test func editorialPreviewHonorsZeroBudget() {
        let items = DiscoverCollectionPreviewPolicy.editorialItems(
            featured: result(id: "featured", title: "Ada Lovelace"),
            todayMostRead: [],
            inTheNews: [],
            trending: [],
            limit: 0
        )

        #expect(items.isEmpty)
    }

    private func result(id: String, title: String) -> WikipediaService.SearchResult {
        WikipediaService.SearchResult(
            id: id,
            title: title,
            description: nil,
            thumbnailURL: nil
        )
    }
}
