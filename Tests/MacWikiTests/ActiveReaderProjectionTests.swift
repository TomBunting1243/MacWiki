import Foundation
import Observation
import Testing

@testable import MacWiki

@MainActor
struct ActiveReaderProjectionTests {
    @Test func placeholderProjectionBecomesArticleProjectionInPlace() {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        store.createNewTab()
        let tabID = store.activeTabId

        #expect(store.activeReaderProjection.activeTabID == tabID)
        #expect(store.activeReaderProjection.isPlaceholder)
        #expect(store.activeReaderProjection.article == nil)
        #expect(store.activeReaderProjection.historyItemID == nil)

        _ = store.openArticle(Article(id: "swift", title: "Swift"))

        #expect(store.activeReaderProjection.activeTabID == tabID)
        #expect(!store.activeReaderProjection.isPlaceholder)
        #expect(store.activeReaderProjection.article?.title == "Swift")
        #expect(store.activeReaderProjection.historyItemID != nil)
    }

    @Test func pureReorderDoesNotPublishReaderProjectionOrMembership() {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "a", title: "A"), inNewTab: true)
        _ = store.openArticle(Article(id: "b", title: "B"), inNewTab: true)
        _ = store.openArticle(Article(id: "c", title: "C"), inNewTab: true)

        let originalProjection = store.activeReaderProjection
        let originalMembership = store.openTabIDs
        let invalidations = ObservationInvalidationCounter()
        withObservationTracking {
            _ = store.activeReaderProjection
            _ = store.openTabIDs
        } onChange: {
            invalidations.increment()
        }

        store.moveTab(from: 0, to: 2)

        #expect(store.openTabs.map(\.title) == ["B", "C", "A"])
        #expect(store.activeReaderProjection == originalProjection)
        #expect(store.openTabIDs == originalMembership)
        #expect(invalidations.value == 0)
    }

    @Test func membershipTracksOpenAndCloseWhileActiveProjectionStaysNarrow() {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "a", title: "A"), inNewTab: true)
        let firstID = store.activeTabId
        _ = store.openArticle(
            Article(id: "b", title: "B"),
            inNewTab: true,
            activateNewTab: false
        )
        let secondID = store.openTabs.last?.id

        #expect(store.openTabIDs == Set([firstID, secondID].compactMap { $0 }))
        #expect(store.activeReaderProjection.article?.title == "A")

        if let secondID {
            store.closeTab(secondID)
        }

        #expect(store.openTabIDs == Set([firstID].compactMap { $0 }))
        #expect(store.activeReaderProjection.article?.title == "A")
    }

    @Test func transientMissingActiveTabPreservesProjectionUntilSelectionChanges() {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "a", title: "A"), inNewTab: true)
        _ = store.openArticle(Article(id: "b", title: "B"), inNewTab: true)
        let outgoingID = store.activeTabId
        let incomingID = store.openTabs.first?.id
        let outgoingProjection = store.activeReaderProjection

        store.openTabs.removeAll { $0.id == outgoingID }

        #expect(store.activeReaderProjection == outgoingProjection)
        #expect(store.openTabIDs == Set([incomingID].compactMap { $0 }))

        store.activeTabId = incomingID

        #expect(store.activeReaderProjection.activeTabID == incomingID)
        #expect(store.activeReaderProjection.article?.title == "A")
    }

    @Test func selectionNavigationAndArticleUpdatesRefreshProjection() {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "a", title: "A"))
        let firstHistoryItemID = store.activeReaderProjection.historyItemID
        _ = store.openArticle(Article(id: "b", title: "B"))
        let secondHistoryItemID = store.activeReaderProjection.historyItemID

        #expect(store.activeReaderProjection.article?.title == "B")
        #expect(store.activeReaderProjection.canGoBack)
        #expect(!store.activeReaderProjection.canGoForward)
        #expect(secondHistoryItemID != firstHistoryItemID)

        store.goBack()

        #expect(store.activeReaderProjection.historyItemID == firstHistoryItemID)
        #expect(store.activeReaderProjection.article?.title == "A")
        #expect(!store.activeReaderProjection.canGoBack)
        #expect(store.activeReaderProjection.canGoForward)

        #expect(store.updateReadState(forTitle: "A", isRead: true))
        #expect(store.updateArticleMetadata(
            ids: ["a"],
            description: "Updated description",
            extract: nil,
            wordCount: 42
        ))
        #expect(store.activeReaderProjection.article?.isRead == true)
        #expect(store.activeReaderProjection.article?.description == "Updated description")
        #expect(store.activeReaderProjection.article?.wordCount == 42)

        _ = store.openArticle(Article(id: "c", title: "C"), inNewTab: true)
        let thirdTabID = store.activeTabId
        let firstTabID = store.openTabs.first?.id
        if let firstTabID {
            #expect(store.selectTab(id: firstTabID))
        }
        #expect(store.activeReaderProjection.activeTabID == firstTabID)
        #expect(store.activeReaderProjection.activeTabID != thirdTabID)
        #expect(store.activeReaderProjection.article?.title == "A")
    }

    @Test func persistedSessionValuesRebuildProjectionAndMembership() throws {
        let activeTabID = try #require(
            UUID(uuidString: "11111111-1111-1111-1111-111111111111")
        )
        let placeholderTabID = try #require(
            UUID(uuidString: "22222222-2222-2222-2222-222222222222")
        )
        let activeTab = ArticleTab(
            id: activeTabID,
            content: .history(
                items: [
                    HistoryItem(article: Article(id: "a", title: "A")),
                    HistoryItem(article: Article(id: "b", title: "B"))
                ],
                currentIndex: 1
            )
        )
        let placeholderTab = ArticleTab(
            id: placeholderTabID,
            content: .placeholder
        )
        let snapshot = TabSessionSnapshot(
            openTabs: [activeTab, placeholderTab],
            activeTabId: activeTab.id,
            recentlyClosedTabs: []
        )
        let restoredSnapshot = try JSONDecoder().decode(
            TabSessionSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let restoredStore = TabSessionStore(persistenceMode: .ephemeral)

        restoredStore.openTabs = restoredSnapshot.openTabs
        restoredStore.activeTabId = restoredSnapshot.activeTabId

        #expect(restoredStore.openTabIDs == Set([activeTab.id, placeholderTab.id]))
        #expect(restoredStore.activeReaderProjection.activeTabID == activeTab.id)
        #expect(restoredStore.activeReaderProjection.article?.title == "B")
        #expect(restoredStore.activeReaderProjection.historyItemID == activeTab.history[1].id)
        #expect(restoredStore.activeReaderProjection.canGoBack)
        #expect(!restoredStore.activeReaderProjection.canGoForward)
    }
}

private final class ObservationInvalidationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
