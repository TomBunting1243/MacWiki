import Foundation
import Testing

@testable import MacWiki

@MainActor
struct TabReorderTests {
    @Test func moveTabLeftToRightAdjacent() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openTabs = [
            ArticleTab(article: Article(id: "a", title: "A")),
            ArticleTab(article: Article(id: "b", title: "B")),
            ArticleTab(article: Article(id: "c", title: "C"))
        ]
        let saveGeneration = appState.tabSessionStore.saveRequestGeneration

        appState.moveTab(from: 0, to: 1)

        #expect(appState.openTabs.map(\.article.title) == ["B", "A", "C"])
        #expect(appState.tabSessionStore.saveRequestGeneration == saveGeneration + 1)
        appState.tabSessionStore.cancelPendingSaveForTesting()
    }

    @Test func moveTabLeftToRightAcrossMultipleTabs() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openTabs = [
            ArticleTab(article: Article(id: "a", title: "A")),
            ArticleTab(article: Article(id: "b", title: "B")),
            ArticleTab(article: Article(id: "c", title: "C")),
            ArticleTab(article: Article(id: "d", title: "D"))
        ]

        appState.moveTab(from: 0, to: 3)

        #expect(appState.openTabs.map(\.article.title) == ["B", "C", "D", "A"])
    }

    @Test func moveTabRightToLeftAdjacent() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openTabs = [
            ArticleTab(article: Article(id: "a", title: "A")),
            ArticleTab(article: Article(id: "b", title: "B")),
            ArticleTab(article: Article(id: "c", title: "C"))
        ]

        appState.moveTab(from: 2, to: 1)

        #expect(appState.openTabs.map(\.article.title) == ["A", "C", "B"])
    }

    @Test func identityReorderMovesMultipleTabsBeforeDestinationInSourceOrder() {
        let appState = AppState(persistenceMode: .ephemeral)
        let tabs = ["A", "B", "C", "D", "E"].map {
            ArticleTab(article: Article(id: $0.lowercased(), title: $0))
        }
        appState.openTabs = tabs

        let changed = appState.reorderTabs(
            [tabs[1].id, tabs[3].id],
            before: tabs[4].id
        )

        #expect(changed)
        #expect(appState.openTabs.map(\.article.title) == ["A", "C", "B", "D", "E"])
    }

    @Test func identityReorderCanAppendAndRejectsUnknownSources() {
        let appState = AppState(persistenceMode: .ephemeral)
        let tabs = ["A", "B", "C"].map {
            ArticleTab(article: Article(id: $0.lowercased(), title: $0))
        }
        appState.openTabs = tabs

        #expect(appState.reorderTabs([tabs[0].id], before: nil))
        #expect(appState.openTabs.map(\.article.title) == ["B", "C", "A"])

        #expect(!appState.reorderTabs([UUID()], before: tabs[1].id))
        #expect(appState.openTabs.map(\.article.title) == ["B", "C", "A"])
    }
}
