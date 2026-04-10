import Testing

@testable import MacWiki

struct WebViewInspectorPublisherTests {
    @Test func deduplicatesTableOfContentsPublications() {
        let publisher = WebViewInspectorPublisher()
        let items = [
            ArticleTableOfContentsItem(id: "history", title: "History", level: 2),
            ArticleTableOfContentsItem(id: "legacy", title: "Legacy", level: 2)
        ]

        #expect(publisher.recordTableOfContents(items) == true)
        #expect(publisher.recordTableOfContents(items) == false)
        #expect(publisher.hasTableOfContents == true)
        #expect(publisher.hasPublishedNonEmptyTOCSinceLoad == true)
    }

    @Test func visibleSectionPublishesOnChangeOrForce() {
        let publisher = WebViewInspectorPublisher()

        #expect(publisher.shouldPublishVisibleSection("intro", force: false) == true)
        #expect(publisher.shouldPublishVisibleSection("intro", force: false) == false)
        #expect(publisher.shouldPublishVisibleSection("intro", force: true) == true)
        #expect(publisher.shouldPublishVisibleSection("history", force: false) == true)
    }
}
