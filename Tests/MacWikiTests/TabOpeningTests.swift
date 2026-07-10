import Testing

@testable import MacWiki

@MainActor
struct TabOpeningTests {
    @Test func openInNewTabCanPreserveActiveTabWhenOpenedInBackground() {
        let appState = AppState(persistenceMode: .ephemeral)
        let first = ArticleTab(article: Article(id: "a", title: "A"))
        appState.openTabs = [first]
        appState.activeTabId = first.id

        appState.openArticleInNewTab(Article(id: "b", title: "B"), activate: false)

        #expect(appState.openTabs.count == 2)
        #expect(appState.openTabs.last?.article.title == "B")
        #expect(appState.activeTabId == first.id)
    }

    @Test func openInNewTabStillActivatesByDefault() {
        let appState = AppState(persistenceMode: .ephemeral)
        let first = ArticleTab(article: Article(id: "a", title: "A"))
        appState.openTabs = [first]
        appState.activeTabId = first.id

        appState.openArticleInNewTab(Article(id: "b", title: "B"))

        #expect(appState.openTabs.count == 2)
        #expect(appState.activeTabId == appState.openTabs.last?.id)
    }

    @Test func backgroundNewTabFallsBackToActiveWhenNoTabIsSelected() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openTabs = []
        appState.activeTabId = nil

        appState.openArticleInNewTab(Article(id: "b", title: "B"), activate: false)

        #expect(appState.openTabs.count == 1)
        #expect(appState.activeTabId == appState.openTabs.first?.id)
    }
}
