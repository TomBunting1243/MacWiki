import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct BugRegressionTests {
    @Test func historyScopedScrollWritesDoNotLeakIntoNewArticle() {
        let appState = AppState()
        appState.openTabs.removeAll()
        appState.activeTabId = nil

        let first = Article(id: "first", title: "First Article")
        appState.openArticle(first)

        guard let tabID = appState.activeTabId,
              let firstHistoryID = appState.openTabs.first?.history.first?.id else {
            #expect(Bool(false))
            return
        }

        appState.setScrollPosition(180, forTabID: tabID, historyItemID: firstHistoryID)
        appState.openArticle(Article(id: "second", title: "Second Article"))

        guard let tabIndex = appState.openTabs.firstIndex(where: { $0.id == tabID }) else {
            #expect(Bool(false))
            return
        }

        let currentIndex = appState.openTabs[tabIndex].currentIndex
        let secondHistoryID = appState.openTabs[tabIndex].history[currentIndex].id

        // Simulate a late telemetry event from the previous article instance.
        appState.setScrollPosition(420, forTabID: tabID, historyItemID: firstHistoryID)

        #expect(appState.scrollPosition(forTabID: tabID, historyItemID: secondHistoryID) == 0)
        #expect(appState.scrollPosition(forTabID: tabID, historyItemID: firstHistoryID) == 420)
    }

    @Test func rapidArticleOpensPreserveRecentEntries() async {
        let appState = AppState()
        appState.openTabs.removeAll()
        appState.activeTabId = nil
        appState.recentArticles.removeAll()

        let first = Article(id: "first", title: "First Article")
        let second = Article(id: "second", title: "Second Article")

        appState.openArticle(first)
        appState.openArticle(second)

        try? await Task.sleep(for: .milliseconds(300))

        #expect(appState.recentArticles.prefix(2).map(\.title) == ["Second Article", "First Article"])
    }

    @Test func batchMetadataUpdateTouchesOnlyRequestedArticles() {
        let appState = AppState()
        appState.openTabs = [
            ArticleTab(article: Article(id: "history-1", title: "History One")),
            ArticleTab(article: Article(id: "history-2", title: "History Two"))
        ]
        appState.activeTabId = appState.openTabs.first?.id
        appState.recentArticles = [
            Article(id: "recent-target", title: "Recent Target"),
            Article(
                id: "recent-other",
                title: "Recent Other",
                description: "Keep me",
                extract: "Existing extract",
                wordCount: 11
            )
        ]

        appState.updateArticleMetadata(
            ids: ["recent-target", "history-2"],
            description: "Updated description",
            extract: "Updated extract",
            wordCount: 321
        )

        #expect(appState.recentArticles[0].description == "Updated description")
        #expect(appState.recentArticles[0].extract == "Updated extract")
        #expect(appState.recentArticles[0].wordCount == 321)

        #expect(appState.recentArticles[1].description == "Keep me")
        #expect(appState.recentArticles[1].extract == "Existing extract")
        #expect(appState.recentArticles[1].wordCount == 11)

        #expect(appState.openTabs[0].history[0].article.description == nil)
        #expect(appState.openTabs[0].history[0].article.extract == nil)
        #expect(appState.openTabs[0].history[0].article.wordCount == nil)

        #expect(appState.openTabs[1].history[0].article.description == "Updated description")
        #expect(appState.openTabs[1].history[0].article.extract == "Updated extract")
        #expect(appState.openTabs[1].history[0].article.wordCount == 321)
    }

    @Test func searchSavePreventsNormalizedDuplicateTitles() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Research")
        modelContext.insert(list)

        let existing = SavedArticle(title: "Swift_programming_language", list: list)
        list.articles.append(existing)

        let result = WikipediaService.SearchResult(
            id: "swift",
            title: "Swift programming language",
            description: nil,
            thumbnailURL: nil
        )

        SearchResultActions.saveToList(result, list: list, modelContext: modelContext)

        #expect(list.articles.count == 1)
    }

    @Test func discoverFeedFallbackIDsUseStablePrefixWhenPageIDMissing() async throws {
        let service = WikipediaService()
        let payload = """
        {
          "tfa": {
            "title": "No Page ID Article"
          }
        }
        """

        let feed = try await service.parseDiscoverFeedPayload(Data(payload.utf8), dateKey: "2026/02/18")
        #expect(feed.featuredArticle?.id.hasPrefix("fallback-") == true)
    }

    @Test func areaInsertPersistsAndFetches() throws {
        let modelContext = try makeInMemoryModelContext()
        let area = Area(name: "Research Folder")
        modelContext.insert(area)
        try modelContext.save()

        let areas = try modelContext.fetch(FetchDescriptor<Area>())
        #expect(areas.contains { $0.name == "Research Folder" && $0.parentId == nil })
    }

    @Test func sortOrderAllocatorStartsAtZeroForEmptyCollection() {
        #expect(SortOrderAllocator.next(for: [Int]()) == 0)
    }

    @Test func sortOrderAllocatorUsesNextHighestOrder() {
        #expect(SortOrderAllocator.next(for: [0, 4, 4, 2]) == 5)
    }

    @Test func sortOrderAllocatorCapsAtIntMax() {
        #expect(SortOrderAllocator.next(for: [Int.max - 1, Int.max]) == Int.max)
    }

    @Test func collapseGuardDetectsSelectedListWithinCollapsingSubtree() {
        let root = UUID()
        let child = UUID()
        let grandchild = UUID()

        let parentAreaByID: [UUID: UUID?] = [
            root: nil,
            child: root,
            grandchild: child
        ]

        let result = SidebarCollapseSelectionGuard.collapseWouldHideSelectedList(
            selectedAreaID: grandchild,
            collapsingAreaID: root,
            parentAreaByID: parentAreaByID
        )

        #expect(result == true)
    }

    @Test func collapseGuardDoesNotTriggerOutsideSubtree() {
        let leftRoot = UUID()
        let leftChild = UUID()
        let rightRoot = UUID()

        let parentAreaByID: [UUID: UUID?] = [
            leftRoot: nil,
            leftChild: leftRoot,
            rightRoot: nil
        ]

        let result = SidebarCollapseSelectionGuard.collapseWouldHideSelectedList(
            selectedAreaID: leftChild,
            collapsingAreaID: rightRoot,
            parentAreaByID: parentAreaByID
        )

        #expect(result == false)
    }

    @Test func collapseGuardHandlesCyclicParentDataSafely() {
        let first = UUID()
        let second = UUID()

        let parentAreaByID: [UUID: UUID?] = [
            first: second,
            second: first
        ]

        let result = SidebarCollapseSelectionGuard.collapseWouldHideSelectedList(
            selectedAreaID: first,
            collapsingAreaID: UUID(),
            parentAreaByID: parentAreaByID
        )

        #expect(result == false)
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            ReadingList.self,
            SavedArticle.self,
            Area.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
