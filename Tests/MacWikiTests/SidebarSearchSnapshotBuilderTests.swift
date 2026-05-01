import Foundation
import Testing

@testable import MacWiki

@MainActor
struct SidebarSearchSnapshotBuilderTests {
    @Test func buildPreservesRelevanceOrderAndStableSourceScopedIDs() {
        let results = [
            searchResult("Grace Hopper", id: "grace"),
            searchResult("Ada Lovelace", id: "ada"),
            searchResult("Katherine Johnson", id: "katherine")
        ]

        let snapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: results,
            sourceKind: .trending,
            readFilter: .all,
            sortMode: .relevance,
            articleIndexes: .empty,
            labels: [],
            currentArticleTitleNormalized: nil
        )
        let rebuilt = SidebarSearchSnapshotBuilder.build(
            sourceResults: results,
            sourceKind: .trending,
            readFilter: .all,
            sortMode: .relevance,
            articleIndexes: .empty,
            labels: [],
            currentArticleTitleNormalized: nil
        )

        #expect(snapshot.rows.map(\.article.title) == ["Grace Hopper", "Ada Lovelace", "Katherine Johnson"])
        #expect(snapshot.rows.map(\.id) == rebuilt.rows.map(\.id))
        #expect(snapshot.rows.first?.id == "trending:grace hopper:grace")
        #expect(
            SidebarSearchSnapshotBuilder.rowID(for: results[0], sourceKind: .query) !=
            SidebarSearchSnapshotBuilder.rowID(for: results[0], sourceKind: .trending)
        )
    }

    @Test func buildSortsByLocalizedTitleAndLengthUsingHydratedThenSavedCounts() {
        let titleSnapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                searchResult("Article 10", id: "10"),
                searchResult("Article 2", id: "2"),
                searchResult("Article 1", id: "1")
            ],
            sourceKind: .query,
            readFilter: .all,
            sortMode: .title,
            articleIndexes: .empty,
            labels: [],
            currentArticleTitleNormalized: nil
        )

        let savedLong = SavedArticle(title: "Saved Long", wordCount: 800)
        let indexes = DirectoryArticleIndexes(
            articleStates: [],
            highlights: [],
            savedArticles: [savedLong]
        )

        let lengthSnapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                searchResult("Unknown", id: "unknown"),
                searchResult("Saved Long", id: "saved-long"),
                searchResult("Hydrated Longest", id: "hydrated-longest")
            ],
            sourceKind: .query,
            readFilter: .all,
            sortMode: .articleLength,
            articleIndexes: indexes,
            labels: [],
            currentArticleTitleNormalized: nil,
            metadataSnapshot: { title in
                guard title == "Hydrated Longest" else { return nil }
                return ArticleMetadataHydrationSnapshot(
                    description: nil,
                    extract: nil,
                    thumbnailURL: nil,
                    wordCount: 1_200
                )
            }
        )

        #expect(titleSnapshot.rows.map(\.article.title) == ["Article 1", "Article 2", "Article 10"])
        #expect(lengthSnapshot.rows.map(\.article.title) == ["Hydrated Longest", "Saved Long", "Unknown"])
        #expect(lengthSnapshot.rows.map(\.resolvedWordCount) == [1_200, 800, nil])
    }

    @Test func buildAppliesUnreadFilterAndReadCountsFromArticleIndexes() {
        let readState = ArticleState(
            articleTitle: "Read Article",
            articleURL: articleURL("Read Article"),
            isRead: true
        )
        let indexes = DirectoryArticleIndexes(
            articleStates: [readState],
            highlights: [],
            savedArticles: []
        )

        let snapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                searchResult("Read Article", id: "read"),
                searchResult("Unread Article", id: "unread")
            ],
            sourceKind: .query,
            readFilter: .unread,
            sortMode: .relevance,
            articleIndexes: indexes,
            labels: [],
            currentArticleTitleNormalized: nil
        )

        #expect(snapshot.sourceCount == 2)
        #expect(snapshot.rows.map(\.article.title) == ["Unread Article"])
        #expect(snapshot.visibleReadCount == 0)
        #expect(snapshot.visibleUnreadCount == 1)
    }

    @Test func buildResolvesSavedLabelTagsCurrentStatusAndProgress() {
        let label = Label(name: "Research", color: .blue)
        let tag = Tag(name: "Spaceflight")
        let list = ReadingList(name: "Mission Queue", icon: "moon")
        let savedArticle = SavedArticle(
            title: "Apollo program",
            description: "Saved description",
            extract: "Saved extract",
            thumbnailURL: URL(string: "https://example.com/apollo.png"),
            list: list,
            wordCount: 2_400
        )
        savedArticle.labelId = label.id
        list.articles = [savedArticle]

        let articleState = ArticleState(
            articleTitle: "Apollo program",
            articleURL: articleURL("Apollo program"),
            isRead: true,
            readingProgress: 0.42
        )
        articleState.tags = [tag]

        let indexes = DirectoryArticleIndexes(
            articleStates: [articleState],
            highlights: [],
            savedArticles: [savedArticle]
        )

        let snapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                searchResult("Apollo program", id: "apollo", description: "Search description")
            ],
            sourceKind: .query,
            readFilter: .all,
            sortMode: .relevance,
            articleIndexes: indexes,
            labels: [label],
            currentArticleTitleNormalized: ReadStateSync.normalizedTitle("Apollo program"),
            liveReadingProgress: { title in
                title == "Apollo program" ? 0.82 : nil
            }
        )

        let row = snapshot.rows[0]
        #expect(row.savedArticle?.title == "Apollo program")
        #expect(row.savedArticle?.readingList?.name == "Mission Queue")
        #expect(row.article.description == "Saved description")
        #expect(row.article.extract == "Saved extract")
        #expect(row.article.thumbnailURL == URL(string: "https://example.com/apollo.png"))
        #expect(row.label?.name == "Research")
        #expect(row.tags.map(\.name) == ["Spaceflight"])
        #expect(row.isRead)
        #expect(row.isCurrent)
        #expect(row.readingProgress == 0.82)
        #expect(row.resolvedWordCount == 2_400)
    }

    @Test func buildFiltersByLabelAndTagBeforeUnreadFilter() {
        let selectedLabel = Label(name: "Research", color: .blue)
        let otherLabel = Label(name: "Archive", color: .gray)
        let selectedTag = Tag(name: "Science")
        let otherTag = Tag(name: "Reference")

        let labeledTagged = SavedArticle(title: "Tagged Match")
        labeledTagged.labelId = selectedLabel.id
        let wrongLabel = SavedArticle(title: "Wrong Label")
        wrongLabel.labelId = otherLabel.id
        let readTagged = SavedArticle(title: "Read Tagged Match")
        readTagged.labelId = selectedLabel.id

        let matchState = ArticleState(
            articleTitle: "Tagged Match",
            articleURL: articleURL("Tagged Match"),
            isRead: false
        )
        matchState.tags = [selectedTag]

        let wrongLabelState = ArticleState(
            articleTitle: "Wrong Label",
            articleURL: articleURL("Wrong Label"),
            isRead: false
        )
        wrongLabelState.tags = [selectedTag]

        let readState = ArticleState(
            articleTitle: "Read Tagged Match",
            articleURL: articleURL("Read Tagged Match"),
            isRead: true
        )
        readState.tags = [selectedTag, otherTag]

        let indexes = DirectoryArticleIndexes(
            articleStates: [matchState, wrongLabelState, readState],
            highlights: [],
            savedArticles: [labeledTagged, wrongLabel, readTagged]
        )

        let snapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                searchResult("Tagged Match", id: "tagged"),
                searchResult("Wrong Label", id: "wrong-label"),
                searchResult("Read Tagged Match", id: "read")
            ],
            sourceKind: .query,
            readFilter: .unread,
            sortMode: .relevance,
            labelFilter: selectedLabel,
            tagFilter: selectedTag,
            articleIndexes: indexes,
            labels: [selectedLabel, otherLabel],
            currentArticleTitleNormalized: nil
        )

        #expect(snapshot.sourceCount == 3)
        #expect(snapshot.scopedCount == 2)
        #expect(snapshot.scopedReadCount == 1)
        #expect(snapshot.scopedUnreadCount == 1)
        #expect(snapshot.rows.map(\.article.title) == ["Tagged Match"])
        #expect(snapshot.visibleReadCount == 0)
        #expect(snapshot.visibleUnreadCount == 1)
    }
}

@MainActor
struct SidebarSearchSurfaceModelTests {
    @Test func selectionReconcilesAcrossReorderDisappearAndSourceSwitch() {
        let coordinator = SearchCoordinator(debounceMilliseconds: 10_000, supportsTrending: true)
        let model = SidebarSearchSurfaceModel(searchCoordinator: coordinator)
        let appState = AppState()
        defer { model.cancel() }

        coordinator.trendingArticles = [
            searchResult("Ada Lovelace", id: "ada"),
            searchResult("Grace Hopper", id: "grace"),
            searchResult("Katherine Johnson", id: "katherine")
        ]
        refresh(model, appState: appState)
        model.reconcileSelection()
        model.select(rowID: SidebarSearchSnapshotBuilder.rowID(for: coordinator.trendingArticles[1], sourceKind: .trending))

        coordinator.trendingArticles = [
            searchResult("Katherine Johnson", id: "katherine"),
            searchResult("Grace Hopper", id: "grace"),
            searchResult("Ada Lovelace", id: "ada")
        ]
        refresh(model, appState: appState)
        model.reconcileSelection()

        #expect(model.selectedRow?.article.title == "Grace Hopper")

        coordinator.trendingArticles = [
            searchResult("Katherine Johnson", id: "katherine"),
            searchResult("Ada Lovelace", id: "ada")
        ]
        refresh(model, appState: appState)
        model.reconcileSelection()

        #expect(model.selectedRow?.article.title == "Katherine Johnson")

        coordinator.searchText = "Ada"
        coordinator.searchResults = [searchResult("Ada Lovelace", id: "ada-query")]
        coordinator.cancel()
        refresh(model, appState: appState)
        model.reconcileSelection()

        #expect(model.visibleSnapshot.sourceKind == .query)
        #expect(model.selectedRow?.article.title == "Ada Lovelace")
        #expect(model.selectedRowID?.hasPrefix("query:") == true)
    }

    @Test func moveSelectionStepsThroughVisibleRows() {
        let coordinator = SearchCoordinator(debounceMilliseconds: 10_000, supportsTrending: true)
        let model = SidebarSearchSurfaceModel(searchCoordinator: coordinator)
        let appState = AppState()
        defer { model.cancel() }

        coordinator.trendingArticles = [
            searchResult("Ada Lovelace", id: "ada"),
            searchResult("Grace Hopper", id: "grace"),
            searchResult("Katherine Johnson", id: "katherine")
        ]
        refresh(model, appState: appState)

        model.moveSelectionDown()
        #expect(model.selectedRow?.article.title == "Ada Lovelace")

        model.moveSelectionDown()
        #expect(model.selectedRow?.article.title == "Grace Hopper")

        model.moveSelectionUp()
        #expect(model.selectedRow?.article.title == "Ada Lovelace")
    }

    @Test func moveSelectionUpStartsAtLastVisibleRowWhenSelectionIsEmpty() {
        let coordinator = SearchCoordinator(debounceMilliseconds: 10_000, supportsTrending: true)
        let model = SidebarSearchSurfaceModel(searchCoordinator: coordinator)
        let appState = AppState()
        defer { model.cancel() }

        coordinator.trendingArticles = [
            searchResult("Ada Lovelace", id: "ada"),
            searchResult("Grace Hopper", id: "grace"),
            searchResult("Katherine Johnson", id: "katherine")
        ]
        refresh(model, appState: appState)

        model.moveSelectionUp()
        #expect(model.selectedRow?.article.title == "Katherine Johnson")
    }

    @Test func displayStateDistinguishesScopeFilterEmptyStates() {
        let coordinator = SearchCoordinator(debounceMilliseconds: 10_000, supportsTrending: true)
        let model = SidebarSearchSurfaceModel(searchCoordinator: coordinator)
        let appState = AppState()
        let label = Label(name: "Research", color: .blue)
        defer { model.cancel() }

        coordinator.searchText = "Ada"
        coordinator.cancel()
        coordinator.searchResults = [searchResult("Ada Lovelace", id: "ada")]

        model.labelFilter = label
        model.refreshArticleIndexes(articleStates: [], highlights: [], savedArticles: [])
        model.refreshVisibleSnapshot(labels: [label], appState: appState)
        #expect(model.displayState == .noFilteredResults)

        let saved = SavedArticle(title: "Ada Lovelace")
        saved.labelId = label.id
        let readState = ArticleState(
            articleTitle: "Ada Lovelace",
            articleURL: articleURL("Ada Lovelace"),
            isRead: true
        )

        model.readFilter = .unread
        model.refreshArticleIndexes(articleStates: [readState], highlights: [], savedArticles: [saved])
        model.refreshVisibleSnapshot(labels: [label], appState: appState)
        #expect(model.displayState == .noUnreadFilteredResults)
    }
}

@MainActor
private func refresh(_ model: SidebarSearchSurfaceModel, appState: AppState) {
    model.refreshArticleIndexes(articleStates: [], highlights: [], savedArticles: [])
    model.refreshVisibleSnapshot(labels: [], appState: appState)
}

private func searchResult(
    _ title: String,
    id: String,
    description: String? = nil,
    thumbnailURL: URL? = nil
) -> WikipediaService.SearchResult {
    WikipediaService.SearchResult(
        id: id,
        title: title,
        description: description,
        thumbnailURL: thumbnailURL
    )
}

private func articleURL(_ title: String) -> URL {
    URL(string: WikipediaURLBuilder.articleURLString(forTitle: title))!
}
