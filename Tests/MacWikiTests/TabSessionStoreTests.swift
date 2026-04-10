import Foundation
import Testing

@testable import MacWiki

@MainActor
struct TabSessionStoreTests {
    @Test func placeholderTabConvertsToArticleHistory() {
        let store = TabSessionStore(loadPersistedState: false)
        store.createNewTab()

        let article = Article(id: "swift", title: "Swift")
        let result = store.openArticle(article)

        #expect(store.openTabs.count == 1)
        #expect(store.currentArticle?.title == "Swift")
        #expect(store.openTabs[0].isPlaceholder == false)
        #expect(store.openTabs[0].history.map(\.article.title) == ["Swift"])
        #expect(store.openTabs[0].currentIndex == 0)
        #expect(result.openedArticle?.title == "Swift")
    }

    @Test func openingAfterBackTruncatesForwardHistory() {
        let store = TabSessionStore(loadPersistedState: false)
        _ = store.openArticle(Article(id: "a", title: "A"))
        _ = store.openArticle(Article(id: "b", title: "B"))

        store.goBack()
        _ = store.openArticle(Article(id: "c", title: "C"))

        #expect(store.openTabs.count == 1)
        #expect(store.openTabs[0].history.map(\.article.title) == ["A", "C"])
        #expect(store.openTabs[0].currentIndex == 1)
    }

    @Test func reopenClosedTabPreservesFullHistoryAndCurrentIndex() {
        let store = TabSessionStore(loadPersistedState: false)
        _ = store.openArticle(Article(id: "a", title: "A"))
        _ = store.openArticle(Article(id: "b", title: "B"))
        _ = store.openArticle(Article(id: "c", title: "C"))
        store.goBack()

        guard let closedID = store.activeTabId else {
            #expect(Bool(false))
            return
        }

        store.closeTab(closedID)
        store.reopenLastClosedTab()

        #expect(store.openTabs.count == 1)
        #expect(store.openTabs[0].history.map(\.article.title) == ["A", "B", "C"])
        #expect(store.openTabs[0].currentIndex == 1)
        #expect(store.currentArticle?.title == "B")
    }

    @Test func duplicateTabPreservesHistoryAndSelection() {
        let store = TabSessionStore(loadPersistedState: false)
        _ = store.openArticle(Article(id: "a", title: "A"))
        _ = store.openArticle(Article(id: "b", title: "B"))
        store.goBack()

        guard let sourceID = store.activeTabId else {
            #expect(Bool(false))
            return
        }

        let sourceTab = store.openTabs[0]
        store.duplicateTab(id: sourceID)

        #expect(store.openTabs.count == 2)
        #expect(store.openTabs[1].id != sourceTab.id)
        #expect(store.openTabs[1].history == sourceTab.history)
        #expect(store.openTabs[1].currentIndex == sourceTab.currentIndex)
        #expect(store.activeTabId == store.openTabs[1].id)
    }

    @Test func closingActiveTabFallsBackToNeighborAtSameIndex() {
        let store = TabSessionStore(loadPersistedState: false)
        _ = store.openArticle(Article(id: "a", title: "A"), inNewTab: true)
        _ = store.openArticle(Article(id: "b", title: "B"), inNewTab: true)
        _ = store.openArticle(Article(id: "c", title: "C"), inNewTab: true)

        let tabBID = store.openTabs[1].id
        store.activeTabId = tabBID
        store.closeTab(tabBID)

        #expect(store.openTabs.map(\.title) == ["A", "C"])
        #expect(store.activeTabId == store.openTabs[1].id)
        #expect(store.currentArticle?.title == "C")
    }

    @Test func snapshotRoundTripPreservesHistoryPlaceholderAndRecentlyClosed() throws {
        let openTab = ArticleTab(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            content: .history(
                items: [
                    HistoryItem(article: Article(id: "a", title: "A")),
                    HistoryItem(article: Article(id: "b", title: "B"))
                ],
                currentIndex: 1
            )
        )
        let placeholderTab = ArticleTab(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            content: .placeholder
        )
        let snapshot = TabSessionSnapshot(
            openTabs: [openTab, placeholderTab],
            activeTabId: placeholderTab.id,
            recentlyClosedTabs: [openTab]
        )

        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(TabSessionSnapshot.self, from: data)

        #expect(restored.version == TabSessionSnapshot.currentVersion)
        #expect(restored.activeTabId == placeholderTab.id)
        #expect(restored.openTabs[0].history.map(\.article.title) == ["A", "B"])
        #expect(restored.openTabs[0].currentIndex == 1)
        #expect(restored.openTabs[1].isPlaceholder == true)
        #expect(restored.recentlyClosedTabs.first?.history.map(\.article.title) == ["A", "B"])
    }
}
