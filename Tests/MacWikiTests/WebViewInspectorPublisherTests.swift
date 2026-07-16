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
        #expect(publisher.shouldPublishVisibleSection(nil, force: false) == true)
        #expect(publisher.lastReportedVisibleSectionId == nil)
    }

    @Test func staleCompletionCannotEndAReplacementProjectionPublish() throws {
        let publisher = WebViewInspectorPublisher()
        let stalePublication = try #require(publisher.beginTableOfContentsPublish())
        #expect(publisher.beginTableOfContentsPublish() == nil)

        publisher.resetForContentReload()
        let currentPublication = try #require(publisher.beginTableOfContentsPublish())
        publisher.endTableOfContentsPublish(stalePublication)

        #expect(publisher.beginTableOfContentsPublish() == nil)
        publisher.endTableOfContentsPublish(currentPublication)
        #expect(publisher.beginTableOfContentsPublish() != nil)
    }

    @Test func staleReferencesCompletionCannotEndReplacementPublication() throws {
        let publisher = WebViewInspectorPublisher()
        let stalePublication = try #require(publisher.beginReferencesPublish())

        publisher.resetForContentReload()
        let currentPublication = try #require(publisher.beginReferencesPublish())
        publisher.endReferencesPublish(stalePublication)

        #expect(publisher.beginReferencesPublish() == nil)
        publisher.endReferencesPublish(currentPublication)
        #expect(publisher.beginReferencesPublish() != nil)
    }

    @Test func asynchronousVisibleQueryCannotOverwriteNewerTelemetry() {
        let publisher = WebViewInspectorPublisher()
        let querySequence = publisher.beginVisibleSectionQuery()

        #expect(publisher.shouldPublishVisibleSection("history", force: false))
        #expect(!publisher.shouldPublishVisibleSection(
            "introduction",
            force: true,
            ifUnchangedSince: querySequence
        ))
        #expect(publisher.lastReportedVisibleSectionId == "history")
    }
}
