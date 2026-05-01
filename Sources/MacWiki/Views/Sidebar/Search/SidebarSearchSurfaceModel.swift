import Foundation
import Observation
import SwiftData

@Observable @MainActor
final class SidebarSearchSurfaceModel {
    let searchCoordinator: SearchCoordinator
    let metadataHydrator: ArticleMetadataHydrator

    var readFilter: SidebarSearchReadFilter = .all
    var sortMode: SidebarSearchSortMode = .relevance
    var labelFilter: Label?
    var tagFilter: Tag?
    var selectedRowID: String?
    var activePageViewsPopover: SidebarSearchPageViewsPopoverPayload?
    private(set) var articleIndexes = DirectoryArticleIndexes.empty
    private(set) var visibleSnapshot = SidebarSearchVisibleSnapshot.empty

    init(
        searchCoordinator: SearchCoordinator = SearchCoordinator(
            debounceMilliseconds: SearchCoordinator.defaultDebounceMilliseconds,
            minimumQueryLength: 2,
            supportsTrending: true,
            searchPrefetchLimit: 24,
            trendingPrefetchLimit: 24
        ),
        metadataHydrator: ArticleMetadataHydrator = ArticleMetadataHydrator()
    ) {
        self.searchCoordinator = searchCoordinator
        self.metadataHydrator = metadataHydrator
    }

    var sourceKind: SidebarSearchSourceKind {
        searchCoordinator.hasQuery ? .query : .trending
    }

    var sourceResults: [WikipediaService.SearchResult] {
        searchCoordinator.hasQuery ? searchCoordinator.searchResults : searchCoordinator.trendingArticles
    }

    var visibleRowIDs: [String] {
        visibleSnapshot.rows.map(\.id)
    }

    var selectedRow: SidebarSearchRow? {
        guard let selectedRowID else { return nil }
        return visibleSnapshot.rows.first { $0.id == selectedRowID }
    }

    var hasActiveViewOptions: Bool {
        readFilter == .unread || labelFilter != nil || tagFilter != nil || sortMode != .relevance
    }

    var hasActiveScopeFilter: Bool {
        labelFilter != nil || tagFilter != nil
    }

    var headerMetadataText: String {
        let sourceLabel = sourceKind == .query ? "Results" : "Top Reads"

        if searchCoordinator.hasQuery {
            if searchCoordinator.isLoading {
                return "Searching · \(countText)"
            }
            if readFilter == .unread && visibleSnapshot.rows.count != searchCoordinator.searchResults.count {
                return "\(sourceLabel) · \(visibleSnapshot.rows.count) of \(searchCoordinator.searchResults.count)"
            }
            return "\(sourceLabel) · \(countText)"
        }

        if searchCoordinator.isTrendingLoading {
            return "Trending"
        }
        if !searchCoordinator.trendingArticles.isEmpty {
            return "\(sourceLabel) · \(countText)"
        }
        return "Wikipedia"
    }

    var countText: String {
        visibleSnapshot.rows.count == 1 ? "1 result" : "\(visibleSnapshot.rows.count) results"
    }

    var displayState: SidebarSearchDisplayState {
        if let errorMessage = searchCoordinator.errorMessage {
            return .error(errorMessage)
        }

        if searchCoordinator.hasQuery {
            if searchCoordinator.isLoading && searchCoordinator.searchResults.isEmpty {
                return .searching(searchCoordinator.searchText)
            }
            if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
                return .noQueryResults(searchCoordinator.searchText)
            }
            if visibleSnapshot.rows.isEmpty && !searchCoordinator.isLoading {
                if hasActiveScopeFilter {
                    return readFilter == .unread && visibleSnapshot.scopedReadCount > 0
                        ? .noUnreadFilteredResults
                        : .noFilteredResults
                }
                return .noUnreadQueryResults
            }
            return .results
        }

        if searchCoordinator.isTrendingLoading {
            return .loadingTrending
        }
        if searchCoordinator.trendingArticles.isEmpty {
            return .emptyPrompt
        }
        if visibleSnapshot.rows.isEmpty {
            if hasActiveScopeFilter {
                return readFilter == .unread && visibleSnapshot.scopedReadCount > 0
                    ? .noUnreadFilteredResults
                    : .noFilteredResults
            }
            return .noUnreadTrending
        }
        return .results
    }

    func refreshArticleIndexes(
        articleStates: [ArticleState],
        highlights: [Highlight],
        savedArticles: [SavedArticle]
    ) {
        articleIndexes = DirectoryArticleIndexes(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    func refreshVisibleSnapshot(labels: [Label], appState: AppState) {
        let currentTitle = DirectoryArticleIndexes.currentArticleTitleNormalized(in: appState)
        visibleSnapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: sourceResults,
            sourceKind: sourceKind,
            readFilter: readFilter,
            sortMode: sortMode,
            labelFilter: labelFilter,
            tagFilter: tagFilter,
            articleIndexes: articleIndexes,
            labels: labels,
            currentArticleTitleNormalized: currentTitle,
            liveReadingProgress: { title in
                appState.liveReadingProgress(forTitle: title)
            },
            metadataSnapshot: { [metadataHydrator] title in
                metadataHydrator.snapshot(for: title)
            }
        )
    }

    func queueMetadataHydration(appState: AppState, modelContext: ModelContext) {
        let requests = sourceResults.prefix(32).map { result in
            let saved = articleIndexes.savedArticle(for: result.title)
            return ArticleMetadataHydrationRequest(
                title: result.title,
                articleID: result.id,
                description: saved?.articleDescription ?? result.description,
                extract: saved?.extract,
                thumbnailURL: saved?.thumbnailURL ?? result.thumbnailURL,
                wordCount: saved?.wordCount,
                savedArticle: saved
            )
        }

        metadataHydrator.queueLoad(
            requests: Array(requests),
            appState: appState,
            modelContext: modelContext
        )
    }

    func clearSelection() {
        selectedRowID = nil
    }

    func reconcileSelection() {
        guard !visibleSnapshot.rows.isEmpty else {
            selectedRowID = nil
            return
        }

        if let selectedRowID,
           visibleSnapshot.rows.contains(where: { $0.id == selectedRowID }) {
            return
        }

        selectedRowID = visibleSnapshot.rows.first?.id
    }

    func select(rowID: String) {
        selectedRowID = rowID
    }

    func toggleLabelFilter(_ label: Label) {
        labelFilter = (labelFilter?.id == label.id) ? nil : label
        reconcileSelection()
    }

    func toggleTagFilter(_ tag: Tag) {
        tagFilter = (tagFilter?.id == tag.id) ? nil : tag
        reconcileSelection()
    }

    func clearLabelFilter() {
        labelFilter = nil
        reconcileSelection()
    }

    func clearTagFilter() {
        tagFilter = nil
        reconcileSelection()
    }

    func resetFilters() {
        readFilter = .all
        sortMode = .relevance
        labelFilter = nil
        tagFilter = nil
        reconcileSelection()
    }

    func moveSelectionDown() {
        moveSelection(offset: 1)
    }

    func moveSelectionUp() {
        moveSelection(offset: -1)
    }

    func presentPageViews(for row: SidebarSearchRow) {
        activePageViewsPopover = SidebarSearchPageViewsPopoverPayload(
            rowID: row.id,
            title: row.article.title
        )
    }

    func dismissPageViews(for rowID: String) {
        guard activePageViewsPopover?.rowID == rowID else { return }
        activePageViewsPopover = nil
    }

    func cancel() {
        searchCoordinator.cancel()
        metadataHydrator.cancel()
    }

    private func moveSelection(offset: Int) {
        guard !visibleSnapshot.rows.isEmpty else {
            selectedRowID = nil
            return
        }

        let rowIDs = visibleSnapshot.rows.map(\.id)
        guard let currentSelectedRowID = selectedRowID,
              let currentIndex = rowIDs.firstIndex(of: currentSelectedRowID)
        else {
            selectedRowID = offset < 0 ? rowIDs.last : rowIDs.first
            return
        }

        let targetIndex = min(max(currentIndex + offset, 0), rowIDs.count - 1)
        selectedRowID = rowIDs[targetIndex]
    }
}
