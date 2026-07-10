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

        appState.moveTab(from: 0, to: 1)

        #expect(appState.openTabs.map(\.article.title) == ["B", "A", "C"])
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
}
