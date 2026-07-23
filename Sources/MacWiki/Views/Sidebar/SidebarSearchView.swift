import SwiftData
import SwiftUI

struct SidebarSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]
    @Query(sort: \ArticleState.updatedAt, order: .reverse) private var articleStates: [ArticleState]
    @Query private var savedArticles: [SavedArticle]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]

    let model: SidebarSearchSurfaceModel
    @Binding var isSearchFieldFocused: Bool

    private var searchSurfaceFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        ))
        hasher.combine(model.searchCoordinator.hasQuery)
        hasher.combine(model.searchCoordinator.isLoading)
        hasher.combine(model.searchCoordinator.isTrendingLoading)
        hasher.combine(model.searchCoordinator.errorMessage)
        hasher.combine(model.readFilter)
        hasher.combine(model.sortMode)
        hasher.combine(model.labelFilter?.id)
        hasher.combine(model.tagFilter?.id)
        hasher.combine(model.sourceResults.count)

        for result in model.sourceResults {
            hasher.combine(result.id)
            hasher.combine(result.title)
            hasher.combine(result.description)
            hasher.combine(result.thumbnailURL?.absoluteString)

            let hydration = model.metadataHydrator.snapshot(for: result.title)
            hasher.combine(hydration?.description)
            hasher.combine(hydration?.extract)
            hasher.combine(hydration?.thumbnailURL?.absoluteString)
            hasher.combine(hydration?.wordCount)
        }

        return hasher.finalize()
    }

    private var metadataHydrationFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(model.sourceResults.count)
        hasher.combine(directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        ))

        for result in model.sourceResults {
            hasher.combine(result.id)
            hasher.combine(ReadStateSync.normalizedTitle(result.title))
            hasher.combine(result.description)
            hasher.combine(result.thumbnailURL?.absoluteString)
        }

        return hasher.finalize()
    }

    var body: some View {
        SidebarSearchContentView(
            model: model,
            allLists: allLists,
            allLabels: allLabels,
            allTags: allTags,
            onRetry: model.searchCoordinator.retrySearch,
            onOpenRow: openRow(_:inNewTab:),
            onToggleRead: toggleReadState(for:)
        )
        .onAppear {
            if let launchQuery = appState.consumeLaunchSidebarSearchQuery() {
                model.searchCoordinator.searchText = launchQuery
            }
            model.searchCoordinator.loadTrendingIfNeeded()
            Task { @MainActor in
                await Task.yield()
                isSearchFieldFocused = true
            }
        }
        .task(id: searchSurfaceFingerprint) {
            await Task.yield()
            refreshSearchState()
        }
        .onChange(of: model.searchCoordinator.searchText) { _, _ in
            model.clearSelection()
        }
        .task(id: metadataHydrationFingerprint) {
            model.queueMetadataHydration(appState: appState, modelContext: modelContext)
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                model.moveSelectionDown()
            case .up:
                model.moveSelectionUp()
            default:
                break
            }
        }
        .onExitCommand(perform: dismissSearch)
        .onDisappear {
            model.cancel()
        }
    }

    private func refreshSearchState() {
        model.refreshDerivedState(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles,
            labels: allLabels,
            appState: appState
        )
        model.reconcileSelection()
    }

    private func openRow(_ row: SidebarSearchRow, inNewTab: Bool) {
        performOpen(row, inNewTab: inNewTab || appState.searchContext == .newTab)
    }

    private func performOpen(_ row: SidebarSearchRow, inNewTab: Bool) {
        model.select(rowID: row.id)
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: row.article)
            return
        }
        appState.openArticle(row.article, inNewTab: inNewTab)
    }

    private func toggleReadState(for row: SidebarSearchRow) {
        Task { @MainActor in
            await Task.yield()
            _ = ReadStateSync.applyReadState(
                !row.isRead,
                for: row.article,
                in: modelContext,
                appState: appState
            )
        }
    }

    private func dismissSearch() {
        withAnimation(reduceMotion ? nil : ColumnMotion.sidebarVisibility) {
            appState.showSearch = false
        }
    }
}
