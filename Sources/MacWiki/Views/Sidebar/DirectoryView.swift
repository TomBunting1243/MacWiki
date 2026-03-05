import SwiftUI
import SwiftData
import Charts

private enum DirectoryReadFilter {
    case all
    case unread
}

private enum DirectorySupplementalSortMode: String, CaseIterable {
    case recent = "Recent"
    case title = "Title"
    case articleLength = "Length"
}

@MainActor
private struct DirectoryArticleIndexes {
    static let empty = DirectoryArticleIndexes(articleStates: [], highlights: [], savedArticles: [])

    private let articleStateByURL: [String: ArticleState]
    private let articleStateByTitle: [String: ArticleState]
    private let highlightsByTitle: [String: [Highlight]]
    private let savedByTitle: [String: SavedArticle]

    init(
        articleStates: [ArticleState],
        highlights: [Highlight],
        savedArticles: [SavedArticle] = []
    ) {
        articleStateByURL = articleStates.reduce(into: [:]) { result, state in
            result[state.articleURLString] = state
        }

        articleStateByTitle = articleStates.reduce(into: [:]) { result, state in
            result[ReadStateSync.normalizedTitle(state.articleTitle)] = state
        }

        highlightsByTitle = highlights.reduce(into: [:]) { result, highlight in
            let key = ReadStateSync.normalizedTitle(highlight.articleTitle)
            result[key, default: []].append(highlight)
        }

        var savedLookup: [String: SavedArticle] = [:]
        for article in savedArticles {
            let key = ReadStateSync.normalizedTitle(article.title)
            if savedLookup[key] == nil {
                savedLookup[key] = article
            }
        }
        savedByTitle = savedLookup
    }

    func articleState(for title: String) -> ArticleState? {
        let urlString = ReadStateSync.urlString(for: title)
        if let state = articleStateByURL[urlString] {
            return state
        }
        return articleStateByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func savedArticle(for title: String) -> SavedArticle? {
        savedByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func cachedHighlights(for title: String) -> [Highlight] {
        highlightsByTitle[ReadStateSync.normalizedTitle(title)] ?? []
    }

    func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        articleState(for: title)?.isRead ?? fallback
    }

    func tagsForArticle(title: String) -> [Tag] {
        var seen = Set<UUID>()
        let stateTags = articleState(for: title)?.tags.sorted { $0.sortOrder < $1.sortOrder } ?? []
        let highlightTags = cachedHighlights(for: title).flatMap { $0.tags }
        return (stateTags + highlightTags).filter { tag in
            if seen.contains(tag.id) { return false }
            seen.insert(tag.id)
            return true
        }
    }

    func articleHasTag(_ title: String, tagId: UUID) -> Bool {
        if articleState(for: title)?.tags.contains(where: { $0.id == tagId }) == true {
            return true
        }
        return cachedHighlights(for: title).contains { highlight in
            highlight.tags.contains(where: { $0.id == tagId })
        }
    }

    func readingProgress(for title: String, in appState: AppState) -> Double {
        if isCurrentArticle(title, in: appState), let live = appState.liveReadingProgress(forTitle: title) {
            return live
        }
        return articleState(for: title)?.readingProgress ?? 0
    }

    func isCurrentArticle(_ title: String, in appState: AppState) -> Bool {
        guard let activeTitle = Self.currentArticleTitleNormalized(in: appState) else { return false }
        return activeTitle == ReadStateSync.normalizedTitle(title)
    }

    static func currentArticleTitleNormalized(in appState: AppState) -> String? {
        guard let activeId = appState.activeTabId,
              let tab = appState.openTabs.first(where: { $0.id == activeId }) else {
            return nil
        }
        return ReadStateSync.normalizedTitle(tab.article.title)
    }
}

@MainActor
private func directoryArticleIndexesFingerprint(
    articleStates: [ArticleState],
    highlights: [Highlight],
    savedArticles: [SavedArticle]
) -> Int {
    var hasher = Hasher()
    hasher.combine(articleStates.count)
    hasher.combine(highlights.count)
    hasher.combine(savedArticles.count)

    for state in articleStates {
        hasher.combine(state.id)
        hasher.combine(state.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(state.tags.count)
        hasher.combine(state.labelId)
    }

    for highlight in highlights {
        hasher.combine(highlight.id)
        hasher.combine(highlight.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(highlight.tags.count)
        hasher.combine(highlight.isArchivedRaw ?? false)
    }

    for article in savedArticles {
        hasher.combine(article.id)
        hasher.combine(article.savedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(article.labelId)
    }

    return hasher.finalize()
}

struct DirectoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("searchPresentationMode") private var searchPresentationMode: SearchPresentationMode = .overlay
    @AppStorage("recentsScope") private var recentsScope: RecentsScope = .currentTab
    @AppStorage("discover.sidebar.timeMachineHidden") private var discoverSidebarTimeMachineHidden = false
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage("features.wikiHopPostV1Enabled") private var wikiHopPostV1Enabled = false
    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection
    var selectedLabel: Label?
    var selectedTag: Tag?
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Query(sort: \ArticleState.updatedAt, order: .reverse) private var articleStates: [ArticleState]
    @Query private var savedArticles: [SavedArticle]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]
    
    @State private var localLabelFilter: Label? = nil
    @State private var localTagFilter: Tag? = nil
    @State private var discoverFeedStore = DiscoverFeedStore()
    @State private var discoverTrendPulseStore = DiscoverTrendPulseStore()
    @State private var selectedDiscoverDate = Date()
    @State private var supplementalReadFilter: DirectoryReadFilter = .all
    @State private var supplementalSortMode: DirectorySupplementalSortMode = .recent
    @State private var chromeAlignedSidebarVisible = true
    @State private var sidebarChromeChoreographyID = UUID()
    @State private var selectedSavedArticleIDs: Set<UUID> = []
    @State private var selectionAnchorSavedArticleID: UUID?
    @State private var showDeleteSelectedConfirmation = false
    @State private var articleIndexesSnapshot = DirectoryArticleIndexes.empty
    @State private var pendingPageViewsRowKey: String?
    @State private var activePageViewsPopover: SidebarPageViewsPopoverPayload?
    @State private var discoverDateLoadTask: Task<Void, Never>?
    @State private var sidebarTimeTravelSkeletonDelayTask: Task<Void, Never>?
    @State private var shouldShowDelayedSidebarTimeTravelSkeleton = false
    @State private var isTimeMachineDatePickerPresented = false
    @State private var timeMachineLensLastDragX: CGFloat?
    @State private var timeMachineLensDragAccumulatedX: CGFloat = 0

    private let wikipediaService = WikipediaService.shared

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }

    private var articleIndexes: DirectoryArticleIndexes {
        articleIndexesSnapshot
    }

    private var articleIndexesFingerprint: Int {
        directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private func articleState(for title: String) -> ArticleState? {
        articleIndexes.articleState(for: title)
    }

    private func savedArticle(for title: String) -> SavedArticle? {
        articleIndexes.savedArticle(for: title)
    }

    private func readingProgress(for title: String) -> Double {
        articleIndexes.readingProgress(for: title, in: appState)
    }

    private func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        articleIndexes.effectiveReadState(for: title, fallback: fallback)
    }

    private func tagsForArticle(title: String) -> [Tag] {
        articleIndexes.tagsForArticle(title: title)
    }

    private func cachedHighlights(for title: String) -> [Highlight] {
        articleIndexes.cachedHighlights(for: title)
    }

    private func tagsForSavedArticle(_ article: SavedArticle) -> [Tag] {
        tagsForArticle(title: article.title)
    }

    private func articleHasTag(_ title: String, tagId: UUID) -> Bool {
        articleIndexes.articleHasTag(title, tagId: tagId)
    }

    private var currentArticleTitleNormalized: String? {
        DirectoryArticleIndexes.currentArticleTitleNormalized(in: appState)
    }

    private func isCurrentArticle(_ title: String) -> Bool {
        currentArticleTitleNormalized == ReadStateSync.normalizedTitle(title)
    }

    private var selectionResetKey: String {
        if let listId = selectedList?.id {
            return "list:\(listId.uuidString)"
        }
        if let labelId = selectedLabel?.id {
            return "label:\(labelId.uuidString)"
        }
        if let tagId = selectedTag?.id {
            return "tag:\(tagId.uuidString)"
        }
        return "root:\(rootSelection.rawValue):\(recentsScope.rawValue)"
    }

    private var pinnedArticleTitles: Set<String> {
        var titles = Set<String>()

        for saved in savedArticles {
            titles.insert(saved.title)
        }

        for highlight in highlights {
            titles.insert(highlight.articleTitle)
        }

        for state in articleStates where state.labelId != nil || !state.tags.isEmpty {
            titles.insert(state.articleTitle)
        }

        return Set(titles.map(ReadStateSync.normalizedTitle))
    }

    private var pinnedArticleFingerprint: Int {
        var hasher = Hasher()
        for title in pinnedArticleTitles.sorted() {
            hasher.combine(title)
        }
        return hasher.finalize()
    }

    private var discoverReferenceDate: Date {
        Calendar.current.startOfDay(for: selectedDiscoverDate)
    }

    private var selectedDiscoverDateKey: String {
        Self.discoverFeedDateFormatter.string(from: discoverReferenceDate)
    }

    private var shouldQueueSidebarTimeTravelSkeleton: Bool {
        guard rootSelection == .discover else { return false }
        guard discoverFeedStore.isLoading else { return false }
        guard let visibleFeed = discoverFeedStore.feed else { return false }
        return visibleFeed.dateKey != selectedDiscoverDateKey
    }

    private var showsSidebarTimeTravelSkeleton: Bool {
        shouldShowDelayedSidebarTimeTravelSkeleton && shouldQueueSidebarTimeTravelSkeleton
    }

    private var discoverTrendReferenceDate: Date {
        guard let dateKey = discoverFeedStore.feed?.dateKey else {
            return discoverReferenceDate
        }
        return Self.discoverFeedDateFormatter.date(from: dateKey) ?? discoverReferenceDate
    }

    private var discoverTrendingItems: [WikipediaService.SearchResult] {
        guard let feed = discoverFeedStore.feed else { return [] }
        return discoverMostReadItems(from: feed)
    }

    private var discoverTrendingPulseLoadKey: String {
        guard rootSelection == .discover, let feed = discoverFeedStore.feed else {
            return "inactive"
        }
        let titleKey = discoverMostReadItems(from: feed).map(\.title).joined(separator: "|")
        return "\(feed.dateKey)|\(titleKey)"
    }

    private func discoverMostReadItems(
        from feed: WikipediaService.DiscoverFeed,
        limit: Int = 24
    ) -> [WikipediaService.SearchResult] {
        let trendingItems = Array(feed.trending.prefix(limit))
        guard trendingItems.isEmpty else { return trendingItems }

        var deduped: [WikipediaService.SearchResult] = []
        var seenTitles = Set<String>()

        func appendUnique(_ items: [WikipediaService.SearchResult]) {
            guard deduped.count < limit else { return }
            for item in items {
                let key = ReadStateSync.normalizedTitle(item.title)
                guard !key.isEmpty else { continue }
                guard seenTitles.insert(key).inserted else { continue }
                deduped.append(item)
                if deduped.count >= limit {
                    break
                }
            }
        }

        appendUnique(feed.inTheNews)
        appendUnique(feed.newsStories.flatMap(\.links))
        let primaryTimeline = feed.onThisDaySelected.isEmpty ? feed.onThisDay : feed.onThisDaySelected
        appendUnique(primaryTimeline.compactMap(\.article))
        appendUnique(feed.didYouKnow.compactMap(\.article))

        return deduped
    }

    private var shouldShowTopDirectoryChrome: Bool {
        selectedList != nil ||
        selectedLabel != nil ||
        selectedTag != nil ||
        rootSelection == .recents
    }

    private var isSidebarSearchPresented: Bool {
        searchPresentationMode == .sidebar && appState.showSearch
    }

    private var topDirectoryTitle: String {
        if let list = selectedList {
            return list.name
        }
        if let label = selectedLabel {
            return label.name
        }
        if let tag = selectedTag {
            return tag.name
        }
        if recentsScope == .currentTab,
           let activeId = appState.activeTabId,
           appState.openTabs.contains(where: { $0.id == activeId }) {
            return "Tab History"
        }
        return "Recent"
    }

    private func refreshArticleIndexesSnapshot() {
        articleIndexesSnapshot = DirectoryArticleIndexes(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private func presentPageViewsPopover(
        for title: String,
        rowKey: String,
        initialPulse: WikipediaService.TrendPulse? = nil,
        referenceDate: Date = Date()
    ) {
        activePageViewsPopover = SidebarPageViewsPopoverPayload(
            rowKey: rowKey,
            title: title,
            initialPulse: initialPulse,
            referenceDate: referenceDate
        )
    }

    private func pageViewsPopoverBinding(for rowKey: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsPopover?.rowKey == rowKey },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsPopover?.rowKey == rowKey {
                    activePageViewsPopover = nil
                }
            }
        )
    }

    @ViewBuilder
    private func pageViewsPopover(for rowKey: String) -> some View {
        if let payload = activePageViewsPopover, payload.rowKey == rowKey {
            SidebarPageViewsPopoverContent(
                title: payload.title,
                referenceDate: payload.referenceDate,
                initialPulse: payload.initialPulse
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSidebarSearchPresented {
                SidebarSearchView()
            } else {
                directoryList
            }
        }
        .onAppear {
            chromeAlignedSidebarVisible = appState.sidebarVisible
            refreshArticleIndexesSnapshot()
            updateSidebarTimeTravelSkeletonVisibility()
        }
        .onChange(of: shouldQueueSidebarTimeTravelSkeleton) { _, _ in
            updateSidebarTimeTravelSkeletonVisibility()
        }
        .onChange(of: articleIndexesFingerprint) { _, _ in
            refreshArticleIndexesSnapshot()
        }
        .onChange(of: selectionResetKey) {
            localLabelFilter = nil
            localTagFilter = nil
            clearSavedArticleSelection()
        }
        .onChange(of: selectedList?.id) { _, _ in
            if selectedList == nil {
                clearSavedArticleSelection()
            }
        }
        .onChange(of: localLabelFilter?.id) { _, _ in
            clearSavedArticleSelection()
        }
        .onChange(of: localTagFilter?.id) { _, _ in
            clearSavedArticleSelection()
        }
        .onChange(of: appState.sidebarVisible) { _, newValue in
            syncSidebarChromeChoreography(sidebarVisible: newValue)
        }
        .onChange(of: selectedDiscoverDate) { _, _ in
            guard rootSelection == .discover else { return }
            activePageViewsPopover = nil
            pendingPageViewsRowKey = nil
            queueDiscoverLoadDebounced()
        }
        .onChange(of: rootSelection) { _, newValue in
            if newValue != .discover {
                discoverDateLoadTask?.cancel()
                discoverFeedStore.cancel()
                discoverTrendPulseStore.cancel()
            }
            updateSidebarTimeTravelSkeletonVisibility()
        }
        .onDisappear {
            sidebarTimeTravelSkeletonDelayTask?.cancel()
            sidebarTimeTravelSkeletonDelayTask = nil
            shouldShowDelayedSidebarTimeTravelSkeleton = false
        }
        .confirmationDialog(
            "Delete selected articles?",
            isPresented: $showDeleteSelectedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelectedSavedArticles()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove \(selectedSavedArticleCount) selected article\(selectedSavedArticleCount == 1 ? "" : "s").")
        }
    }

    /// Total height of the pinned directory chrome (title + divider + controls).
    private var directoryTopChromeHeight: CGFloat {
        // title bar height + 0.5 divider + controls bar height (same as topBarHeight)
        directoryTitleBarHeight + 0.5 + ColumnChromeMetrics.topBarHeight
    }

    private var directoryList: some View {
        ZStack(alignment: .top) {
            Group {
                List {
                    directoryContent
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    // Push scroll content below the chrome overlay (or at least
                    // below the traffic-lights region when there is no chrome).
                    Color.clear.frame(height: shouldShowTopDirectoryChrome
                        ? directoryTopChromeHeight
                        : ColumnChromeMetrics.trafficLightsClearance)
                }
                .scrollContentBackground(.hidden)

                if shouldShowTopDirectoryChrome {
                    directoryTopChrome
                }

                if shouldShowRecentsEmptyStateOverlay {
                    recentsEmptyStateOverlay
                }
            }
            .opacity(showsSidebarTimeTravelSkeleton ? 0.30 : 1)
            .blur(radius: showsSidebarTimeTravelSkeleton && !reduceMotion ? 1.1 : 0)
            .allowsHitTesting(!showsSidebarTimeTravelSkeleton)

            if showsSidebarTimeTravelSkeleton {
                SidebarTimeTravelSkeletonOverlay(
                    dateLabel: discoverTimeMachineLongDateLabel,
                    topInset: shouldShowTopDirectoryChrome
                        ? directoryTopChromeHeight
                        : ColumnChromeMetrics.trafficLightsClearance
                )
                .transition(AppLoadingMotion.overlayTransition(reduceMotion: reduceMotion, anchor: .top))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsSidebarTimeTravelSkeleton)
        .background {
            SidebarPaneBackground()
        }
        .ignoresSafeArea(.container, edges: .top)
        .task(id: selectedList?.id) {
            guard let list = selectedList else { return }
            await fetchMissingExtracts(for: list)
        }
        .task(id: rootSelection) {
            if rootSelection == .discover {
                discoverFeedStore.queueLoad(referenceDate: discoverReferenceDate, forceRefresh: false)
            }
        }
        .task(id: discoverTrendingPulseLoadKey) {
            guard rootSelection == .discover else {
                discoverTrendPulseStore.cancel()
                return
            }
            discoverTrendPulseStore.queueLoad(
                results: discoverTrendingItems,
                referenceDate: discoverTrendReferenceDate
            )
        }
        .task(id: pinnedArticleFingerprint) {
            await wikipediaService.replacePinnedArticleTitles(Array(pinnedArticleTitles))
        }
    }

    private static let discoverFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private var shouldShowRecentsEmptyStateOverlay: Bool {
        guard selectedList == nil,
              selectedLabel == nil,
              selectedTag == nil else {
            return false
        }
        guard rootSelection != .discover else { return false }
        guard !(rootSelection == .wikiHop && isWikiHopAvailable) else { return false }

        if recentsScope == .currentTab,
           let activeId = appState.activeTabId,
           appState.openTabs.contains(where: { $0.id == activeId }) {
            return false
        }

        return appState.recentArticles.isEmpty
    }

    private var recentsEmptyStateOverlay: some View {
        VStack(spacing: 0) {
            Color.clear.frame(
                height: shouldShowTopDirectoryChrome
                    ? directoryTopChromeHeight
                    : ColumnChromeMetrics.trafficLightsClearance
            )

            ColumnEmptyStateView(
                title: "No Recent Articles",
                systemImage: "doc.text",
                description: "Search for an article to get started",
                style: .quiet
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var directoryContent: some View {
        if let list = selectedList {
            selectedListSection(list)
        } else if let label = selectedLabel {
            LabelArticlesView(
                label: label,
                labels: labels,
                allTags: tags,
                allLists: allLists,
                savedArticles: savedArticles,
                articleStates: articleStates,
                highlights: highlights,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
        } else if let tag = selectedTag {
            TagArticlesView(
                tag: tag,
                allTags: tags,
                allLists: allLists,
                allLabels: labels,
                savedArticles: savedArticles,
                articleStates: articleStates,
                allHighlights: highlights,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
        } else if rootSelection == .discover {
            discoverSections()
        } else if rootSelection == .wikiHop, isWikiHopAvailable {
            WikiHopLobbyView()
        } else if recentsScope == .currentTab,
                  let activeId = appState.activeTabId,
                  let tab = appState.openTabs.first(where: { $0.id == activeId }) {
            tabHistorySection(tab: tab)
        } else if appState.recentArticles.isEmpty {
            EmptyView()
        } else {
            recentArticlesSection()
        }
    }

    @ViewBuilder
    private func selectedListSection(_ list: ReadingList) -> some View {
        Section {
            if filteredArticles(for: list).isEmpty {
                if list.articles.isEmpty {
                    Text("No articles")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                } else {
                    Text("No \(list.filterMode.rawValue.lowercased()) articles")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            } else {
                ForEach(sortedArticles(for: list)) { savedArticle in
                    let isRead = effectiveReadState(for: savedArticle.title, fallback: savedArticle.isRead)
                    let progress = readingProgress(for: savedArticle.title)
                    let tags = tagsForSavedArticle(savedArticle)
                    SavedArticleRow(
                        savedArticle: savedArticle,
                        isRead: isRead,
                        readProgress: progress,
                        isCurrent: isCurrentArticle(savedArticle.title),
                        list: list,
                        allLists: allLists,
                        allLabels: labels,
                        onToggleRead: { toggleReadStatus(savedArticle) },
                        onMove: { target in moveArticle(savedArticle, from: list, to: target) },
                        onRemove: { removeFromList(savedArticle, list: list) },
                        onLabelClick: { label in
                            localLabelFilter = label
                        },
                        tags: tags,
                        allTags: self.tags,
                        selectedTagId: localTagFilter?.id,
                        onTagClick: { tag in
                            localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                        },
                        isSelected: selectedSavedArticleIDs.contains(savedArticle.id),
                        onOpenArticle: { _ in
                            handleSavedArticlePrimaryAction(savedArticle)
                        },
                        onNewLabel: { article in
                            onNewLabelWithArticle(article)
                        },
                        onNewTag: { article in
                            onNewTagWithArticle(article)
                        }
                    )
                }
            }
        }
    }

    /// Fetch extracts for articles that don't have them
    private func fetchMissingExtracts(for list: ReadingList) async {
        let service = WikipediaService.shared
        // Get titles that need fetching first to avoid iteration issues
        let articlesToFetch = list.articles.filter { $0.extract == nil }.map { $0.title }
        var didMutate = false

        for title in articlesToFetch {
            do {
                let summary = try await service.fetchSummary(title)
                guard !Task.isCancelled else { return }

                // Find the article again in case the list changed
                if let article = list.articles.first(where: { $0.title == title }) {
                    article.extract = summary.extract
                    if article.articleDescription == nil {
                        article.articleDescription = summary.description
                    }
                    if article.thumbnailURLString == nil {
                        article.thumbnailURLString = summary.thumbnailURL?.absoluteString
                    }
                    didMutate = true
                }
            } catch {
                // Silently fail for individual articles
            }
        }

        if didMutate {
            try? modelContext.save()
        }
    }

    /// Deduplicate history items, keeping the most recent occurrence of each article
    private func deduplicatedHistory(_ history: [HistoryItem]) -> [HistoryItem] {
        var seen = Set<String>()
        var result: [HistoryItem] = []
        for item in history.reversed() {
            let normalized = item.article.title.lowercased()
            if !seen.contains(normalized) {
                seen.insert(normalized)
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Directory Controls

    /// Height that the title bar occupies — always tall enough to position
    /// the title text below the traffic-lights region.
    private var directoryTitleBarHeight: CGFloat {
        max(
            appState.windowTopObscuredHeight,
            chromeAlignedSidebarVisible ? ColumnChromeMetrics.titleBarClearance : (ColumnChromeMetrics.titleBarClearance + 14)
        )
    }

    /// When sidebar is collapsed, this column becomes leftmost near traffic lights.
    /// Keep title-to-controls rhythm consistent with the expanded-sidebar state.
    private var directoryTitleBottomPadding: CGFloat {
        6
    }

    private var directoryTopChrome: some View {
        VStack(spacing: 0) {
            directoryTitleBar

            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                .frame(height: 0.5)

            directoryControlsBar
        }
        .background {
            ColumnChromeBackground()
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
    }

    private var directoryTitleBar: some View {
        ZStack(alignment: .bottomLeading) {
            WindowDragHandle(minLength: 140)
                .frame(maxWidth: .infinity)

            HStack(spacing: 10) {
                Text(topDirectoryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, directoryTitleBottomPadding)
        }
        .frame(height: directoryTitleBarHeight)
    }

    private func syncSidebarChromeChoreography(sidebarVisible: Bool) {
        sidebarChromeChoreographyID = UUID()
        let choreographyID = sidebarChromeChoreographyID

        if sidebarVisible {
            DispatchQueue.main.asyncAfter(deadline: .now() + ColumnMotion.sidebarRevealFollowDelay) {
                guard choreographyID == sidebarChromeChoreographyID else { return }
                guard appState.sidebarVisible else { return }
                withAnimation(ColumnMotion.sidebarVisibility) {
                    chromeAlignedSidebarVisible = true
                }
            }
        } else {
            withAnimation(ColumnMotion.sidebarVisibility) {
                chromeAlignedSidebarVisible = false
            }
        }
    }

    private var directoryControlsBar: some View {
        let count = directoryVisibleArticleCount
        let unreadFilterEnabled = isUnreadFilterEnabled
        let sortMode = activeDirectorySortMode

        return ZStack {
            WindowDragHandle(minLength: 80)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                Button {
                    toggleUnreadFilter()
                } label: {
                    Image(systemName: unreadFilterEnabled ? "circle.inset.filled" : "circle")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(unreadFilterEnabled ? Color.accentColor : .secondary)
                        .frame(width: ChromeIconMetrics.buttonSize, height: ChromeIconMetrics.buttonSize)
                        }
                .buttonStyle(.plain)
                .help(unreadFilterEnabled ? "Show all articles" : "Show unread only")

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                + Text(" ")
                + Text(count == 1 ? "article" : "articles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                if hasSelectedSavedArticles {
                    Text("·")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("\(selectedSavedArticleCount) selected")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Menu {
                    ForEach(DirectorySupplementalSortMode.allCases, id: \.self) { mode in
                        Button {
                            setDirectorySortMode(mode)
                        } label: {
                            HStack {
                                Text(mode.rawValue)
                                if sortMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: ChromeIconMetrics.buttonSize, height: ChromeIconMetrics.buttonSize)
                }
                .menuStyle(.borderlessButton)
                .help("Sort")

                Menu {
                    if hasSelectedSavedArticles {
                        Button("Clear Selection") {
                            clearSavedArticleSelection()
                        }

                        if !labels.isEmpty {
                            Menu("Set Label on Selected") {
                                Button("None") {
                                    applyLabelToSelectedSavedArticles(nil)
                                }
                                Divider()
                                ForEach(labels) { label in
                                    Button(label.name) {
                                        applyLabelToSelectedSavedArticles(label.id)
                                    }
                                }
                            }
                        }

                        if !tags.isEmpty {
                            Menu("Add Tag to Selected") {
                                ForEach(tags) { tag in
                                    Button(tag.name) {
                                        addTagToSelectedSavedArticles(tag)
                                    }
                                }
                            }

                            Menu("Remove Tag from Selected") {
                                ForEach(tags) { tag in
                                    Button(tag.name) {
                                        removeTagFromSelectedSavedArticles(tag)
                                    }
                                }
                            }
                        }

                        if !selectionEligibleTargetLists.isEmpty {
                            Menu("Add Selected to List") {
                                ForEach(selectionEligibleTargetLists) { list in
                                    Button(list.name) {
                                        addSelectedSavedArticles(to: list)
                                    }
                                }
                            }
                        }

                        Divider()

                        Button(role: .destructive) {
                            showDeleteSelectedConfirmation = true
                        } label: {
                            SwiftUI.Label("Delete Selected", systemImage: "trash")
                        }

                        Divider()
                    }

                    Button {
                        batchMarkVisibleArticles(asRead: true)
                    } label: {
                        SwiftUI.Label("Mark Visible as Read", systemImage: "checkmark.circle")
                    }
                    .disabled(visibleUnreadCount == 0)

                    Button {
                        batchMarkVisibleArticles(asRead: false)
                    } label: {
                        SwiftUI.Label("Mark Visible as Unread", systemImage: "circle")
                    }
                    .disabled(visibleReadCount == 0)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: ChromeIconMetrics.buttonSize, height: ChromeIconMetrics.buttonSize)
                }
                .menuStyle(.borderlessButton)
                .help("Batch actions")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: ColumnChromeMetrics.topBarHeight - 2)
    }

    private var isUnreadFilterEnabled: Bool {
        if let list = selectedList {
            return list.filterMode == .unread
        }
        return supplementalReadFilter == .unread
    }

    private func toggleUnreadFilter() {
        if let list = selectedList {
            list.filterMode = (list.filterMode == .unread) ? .all : .unread
            try? modelContext.save()
        } else {
            supplementalReadFilter = (supplementalReadFilter == .unread) ? .all : .unread
        }
    }

    private var activeDirectorySortMode: DirectorySupplementalSortMode {
        if let list = selectedList {
            switch list.sortMode {
            case .title:
                return .title
            case .articleLength:
                return .articleLength
            case .addedDate, .manual:
                return .recent
            }
        }
        return supplementalSortMode
    }

    private func setDirectorySortMode(_ mode: DirectorySupplementalSortMode) {
        if let list = selectedList {
            switch mode {
            case .recent:
                list.sortMode = .addedDate
            case .title:
                list.sortMode = .title
            case .articleLength:
                list.sortMode = .articleLength
            }
            try? modelContext.save()
        } else {
            supplementalSortMode = mode
        }
    }

    private func sortedSupplementalSavedArticles(_ articles: [SavedArticle]) -> [SavedArticle] {
        switch supplementalSortMode {
        case .recent:
            return articles.sorted { $0.savedAt > $1.savedAt }
        case .title:
            return articles.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            return articles.sorted { $0.approximateLength > $1.approximateLength }
        }
    }

    private func sortedSupplementalArticles(_ articles: [Article]) -> [Article] {
        switch supplementalSortMode {
        case .recent:
            return articles
        case .title:
            return articles.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            return articles.sorted { ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        }
    }

    private func filteredLabelArticles(for label: Label) -> [SavedArticle] {
        var scoped = savedArticles.filter { $0.labelId == label.id }

        if supplementalReadFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.title, fallback: $0.isRead) }
        }

        return sortedSupplementalSavedArticles(scoped)
    }

    private func taggedArticles(for tag: Tag) -> [Article] {
        var latestByTitle: [String: Date] = [:]

        for highlight in highlights where highlight.tags.contains(where: { $0.id == tag.id }) {
            let current = latestByTitle[highlight.articleTitle] ?? .distantPast
            if highlight.createdAt > current {
                latestByTitle[highlight.articleTitle] = highlight.createdAt
            }
        }

        for state in articleStates where state.tags.contains(where: { $0.id == tag.id }) {
            let current = latestByTitle[state.articleTitle] ?? .distantPast
            if state.updatedAt > current {
                latestByTitle[state.articleTitle] = state.updatedAt
            }
        }

        let orderedTitles = latestByTitle
            .sorted { $0.value > $1.value }
            .map(\.key)

        return orderedTitles.map { title in
            if let saved = savedArticle(for: title) {
                return Article(
                    id: saved.title,
                    title: saved.title,
                    description: saved.articleDescription,
                    extract: saved.extract,
                    thumbnailURL: saved.thumbnailURL,
                    isRead: effectiveReadState(for: saved.title, fallback: saved.isRead),
                    wordCount: saved.wordCount
                )
            }

            return Article(
                id: title,
                title: title,
                isRead: effectiveReadState(for: title, fallback: false)
            )
        }
    }

    private func filteredTaggedArticles(for tag: Tag) -> [Article] {
        var scoped = taggedArticles(for: tag)

        if supplementalReadFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.title, fallback: $0.isRead) }
        }

        return sortedSupplementalArticles(scoped)
    }

    private func filteredTabHistoryItems(for tab: ArticleTab) -> [HistoryItem] {
        var scoped = deduplicatedHistory(tab.history)

        if let tag = localTagFilter {
            scoped = scoped.filter { articleHasTag($0.article.title, tagId: tag.id) }
        }

        if supplementalReadFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.article.title, fallback: $0.article.isRead) }
        }

        switch supplementalSortMode {
        case .recent:
            return scoped
        case .title:
            return scoped.sorted { $0.article.title.localizedCompare($1.article.title) == .orderedAscending }
        case .articleLength:
            return scoped.sorted { ($0.article.wordCount ?? 0) > ($1.article.wordCount ?? 0) }
        }
    }

    private func filteredRecentArticles() -> [Article] {
        var scoped = appState.recentArticles

        if let tag = localTagFilter {
            scoped = scoped.filter { articleHasTag($0.title, tagId: tag.id) }
        }

        if supplementalReadFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.title, fallback: $0.isRead) }
        }

        return sortedSupplementalArticles(scoped)
    }

    private var directoryVisibleTitles: [String] {
        if let list = selectedList {
            return sortedArticles(for: list).map(\.title)
        }

        if let label = selectedLabel {
            return filteredLabelArticles(for: label).map(\.title)
        }

        if let tag = selectedTag {
            return filteredTaggedArticles(for: tag).map(\.title)
        }

        if recentsScope == .currentTab,
           let activeId = appState.activeTabId,
           let tab = appState.openTabs.first(where: { $0.id == activeId }) {
            return filteredTabHistoryItems(for: tab).map(\.article.title)
        }

        return filteredRecentArticles().map(\.title)
    }

    private var directoryVisibleArticleCount: Int {
        directoryVisibleTitles.count
    }

    private var canMultiSelectSavedArticles: Bool {
        selectedList != nil
    }

    private var selectedSavedArticleCount: Int {
        selectedSavedArticleIDs.count
    }

    private var hasSelectedSavedArticles: Bool {
        selectedSavedArticleCount > 0
    }

    private var orderedVisibleSavedArticles: [SavedArticle] {
        guard let list = selectedList else { return [] }
        return sortedArticles(for: list)
    }

    private var orderedVisibleSavedArticleIDs: [UUID] {
        orderedVisibleSavedArticles.map(\.id)
    }

    private var selectedSavedArticles: [SavedArticle] {
        let selectedIDs = selectedSavedArticleIDs
        guard !selectedIDs.isEmpty else { return [] }
        return savedArticles.filter { selectedIDs.contains($0.id) }
    }

    private var selectionEligibleTargetLists: [ReadingList] {
        if let activeList = selectedList {
            return allLists.filter { $0.id != activeList.id }
        }
        return allLists
    }

    private var visibleUnreadCount: Int {
        directoryVisibleTitles.filter { title in
            !effectiveReadState(for: title, fallback: false)
        }.count
    }

    private var visibleReadCount: Int {
        directoryVisibleTitles.filter { title in
            effectiveReadState(for: title, fallback: false)
        }.count
    }

    private func clearSavedArticleSelection() {
        selectedSavedArticleIDs = []
        selectionAnchorSavedArticleID = nil
    }

    private func handleSavedArticlePrimaryAction(_ savedArticle: SavedArticle) {
        let article = Article(
            id: savedArticle.title,
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            extract: savedArticle.extract,
            thumbnailURL: savedArticle.thumbnailURL,
            isRead: effectiveReadState(for: savedArticle.title, fallback: savedArticle.isRead),
            wordCount: savedArticle.wordCount
        )

        if canMultiSelectSavedArticles && SystemBridge.isShiftPressed {
            updateRangeSelection(with: savedArticle.id)
            return
        }

        clearSavedArticleSelection()
        selectionAnchorSavedArticleID = savedArticle.id
        openArticleFromPrimaryClick(article, inNewTab: SystemBridge.isCommandPressed)
    }

    private func openArticleFromPrimaryClick(_ article: Article, inNewTab: Bool) {
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: article)
            return
        }
        appState.openArticle(article, inNewTab: inNewTab)
    }

    private func updateRangeSelection(with tappedID: UUID) {
        let orderedIDs = orderedVisibleSavedArticleIDs
        guard let tappedIndex = orderedIDs.firstIndex(of: tappedID) else { return }

        if selectionAnchorSavedArticleID == nil {
            selectionAnchorSavedArticleID = tappedID
        }

        guard
            let anchorID = selectionAnchorSavedArticleID,
            let anchorIndex = orderedIDs.firstIndex(of: anchorID)
        else {
            selectedSavedArticleIDs = [tappedID]
            selectionAnchorSavedArticleID = tappedID
            return
        }

        let lowerBound = min(anchorIndex, tappedIndex)
        let upperBound = max(anchorIndex, tappedIndex)
        selectedSavedArticleIDs = Set(orderedIDs[lowerBound...upperBound])
    }

    private func batchMarkVisibleArticles(asRead: Bool) {
        let titles = Set(directoryVisibleTitles)
        for title in titles {
            let article = Article(id: title, title: title, isRead: asRead)
            _ = ReadStateSync.applyReadState(asRead, for: article, in: modelContext, appState: appState)
        }

        if let list = selectedList {
            list.updatedAt = Date()
        }

        try? modelContext.save()
    }
    
    // MARK: - Filtering & Sorting
    
    private func filteredArticles(for list: ReadingList) -> [SavedArticle] {
        let baseArticles: [SavedArticle] = {
            switch list.filterMode {
            case .all:
                return list.articles
            case .unread:
                return list.articles.filter { !effectiveReadState(for: $0.title, fallback: $0.isRead) }
            case .read:
                return list.articles.filter { effectiveReadState(for: $0.title, fallback: $0.isRead) }
            }
        }()
        
        var filtered = baseArticles

        if let filter = localLabelFilter {
            filtered = filtered.filter { $0.labelId == filter.id }
        }

        if let tagFilter = localTagFilter {
            filtered = filtered.filter { articleHasTag($0.title, tagId: tagFilter.id) }
        }

        return filtered
    }
    
    private func sortedArticles(for list: ReadingList) -> [SavedArticle] {
        let filtered = filteredArticles(for: list)

        switch list.sortMode {
        case .addedDate:
            return filtered.sorted { $0.savedAt > $1.savedAt }
        case .title:
            return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .manual:
            return filtered.sorted { $0.manualOrder < $1.manualOrder }
        case .articleLength:
            return filtered.sorted { $0.approximateLength > $1.approximateLength }
        }
    }
    
    private func toggleReadStatus(_ article: SavedArticle) {
        let current = effectiveReadState(for: article.title, fallback: article.isRead)
        let newValue = !current
        let resolvedArticle = Article(
            id: article.title,
            title: article.title,
            description: article.articleDescription,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            isRead: newValue,
            wordCount: article.wordCount
        )
        _ = ReadStateSync.applyReadState(newValue, for: resolvedArticle, in: modelContext, appState: appState)
    }
    
    @ViewBuilder
    private func tagFilterRow(tag: Tag) -> some View {
        HStack(spacing: 6) {
            TagChipView(title: tag.name, isSelected: true)

            Button {
                localTagFilter = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions

    private func applyLabelToSelectedSavedArticles(_ labelId: UUID?) {
        guard hasSelectedSavedArticles else { return }

        for article in selectedSavedArticles {
            article.labelId = labelId
            if let state = articleState(for: article.title) {
                state.labelId = labelId
                state.updatedAt = Date()
            }
            article.readingList?.updatedAt = Date()
        }

        try? modelContext.save()
    }

    private func addTagToSelectedSavedArticles(_ tag: Tag) {
        guard hasSelectedSavedArticles else { return }

        for article in selectedSavedArticles {
            guard let state = ensureArticleState(for: article.title) else { continue }
            if !state.tags.contains(where: { $0.id == tag.id }) {
                state.tags.append(tag)
            }
            state.updatedAt = Date()
        }

        try? modelContext.save()
    }

    private func removeTagFromSelectedSavedArticles(_ tag: Tag) {
        guard hasSelectedSavedArticles else { return }

        for article in selectedSavedArticles {
            guard let state = articleState(for: article.title) else { continue }
            state.tags.removeAll { $0.id == tag.id }
            state.updatedAt = Date()
        }

        try? modelContext.save()
    }

    private func addSelectedSavedArticles(to targetList: ReadingList) {
        guard hasSelectedSavedArticles else { return }

        for article in selectedSavedArticles {
            if article.readingList?.id == targetList.id {
                continue
            }

            let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
            if targetList.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalizedTitle }) {
                continue
            }

            let copied = SavedArticle(
                title: article.title,
                description: article.articleDescription,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL,
                list: targetList,
                wordCount: article.wordCount
            )
            copied.isRead = article.isRead
            copied.labelId = article.labelId
            targetList.articles.append(copied)
        }

        targetList.updatedAt = Date()
        try? modelContext.save()
    }

    private func deleteSelectedSavedArticles() {
        guard hasSelectedSavedArticles else { return }

        let targets = selectedSavedArticles
        for article in targets {
            if let list = article.readingList {
                list.articles.removeAll { $0.id == article.id }
                list.updatedAt = Date()
            } else {
                modelContext.delete(article)
            }
        }

        try? modelContext.save()
        clearSavedArticleSelection()
    }

    private func ensureArticleState(for title: String) -> ArticleState? {
        let urlString = ReadStateSync.urlString(for: title)
        let descriptor = FetchDescriptor<ArticleState>(predicate: #Predicate { $0.articleURLString == urlString })
        if let existingState = try? modelContext.fetch(descriptor).first {
            return existingState
        }
        guard let url = URL(string: urlString) else { return nil }
        let newState = ArticleState(articleTitle: title, articleURL: url)
        modelContext.insert(newState)
        return newState
    }
    
    private func saveToList(_ article: Article, list: ReadingList) {
        let saved = SavedArticle(
            title: article.title,
            description: article.description,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            list: list,
            wordCount: article.wordCount
        )
        saved.isRead = ReadStateSync.resolveReadState(for: article, in: modelContext)
        list.articles.append(saved)
        list.updatedAt = Date()
        try? modelContext.save()
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
    }
    
    private func removeFromList(_ article: SavedArticle, list: ReadingList) {
        if let index = list.articles.firstIndex(where: { $0.id == article.id }) {
            list.articles.remove(at: index)
            list.updatedAt = Date()
            try? modelContext.save()
        }
    }

    private func removeSavedArticle(_ article: SavedArticle) {
        if let list = article.readingList {
            removeFromList(article, list: list)
        } else {
            modelContext.delete(article)
            try? modelContext.save()
        }
    }
    
    private func moveArticle(_ article: SavedArticle, from source: ReadingList?, to target: ReadingList) {
        // Create new article in target, preserving extract
        let newArticle = SavedArticle(
            title: article.title,
            description: article.articleDescription,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            list: target
        )
        newArticle.isRead = article.isRead
        newArticle.labelId = article.labelId
        newArticle.wordCount = article.wordCount
        target.articles.append(newArticle)
        target.updatedAt = Date()
        
        // Remove from source or delete if no source
        if let source = source {
            removeFromList(article, list: source)
        } else {
            modelContext.delete(article)
            try? modelContext.save()
        }
    }
    
    private func copyToClipboard(_ text: String) {
        _ = SystemBridge.copyText(text)
    }
    
    private func toggleTag(_ tag: Tag, for article: Article) {
        if let state = articleState(for: article.title) {
            if let index = state.tags.firstIndex(where: { $0.id == tag.id }) {
                state.tags.remove(at: index)
            } else {
                state.tags.append(tag)
            }
            state.updatedAt = Date()
        } else {
             let newState = ArticleState(articleTitle: article.title, articleURL: article.url)
             newState.tags.append(tag)
             modelContext.insert(newState)
        }
        try? modelContext.save()
    }
}
/// Wrapper for list items with hover state and read indicator
struct ArticleListItem<Content: View>: View {
    let isRead: Bool
    let progress: Double
    let isCurrent: Bool
    let isSelected: Bool
    let onToggleRead: (() -> Void)?
    let onTap: () -> Void
    let label: Label?
    @ViewBuilder let content: (Bool, Label?) -> Content
    
    @AppStorage("labelDisplayMode") private var labelDisplayMode: LabelDisplayMode = .rowHighlight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    @State private var isHovered = false

    private var rowCornerRadius: CGFloat { 10 }

    private var rowFill: Color {
        let isKeyWindow = controlActiveState == .key
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? (isKeyWindow ? 0.22 : 0.16) : (isKeyWindow ? 0.18 : 0.14))
        }
        if isCurrent {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.12 : 0.09)
        }
        if isHovered {
            return colorScheme == .dark
                ? Color.white.opacity(isKeyWindow ? 0.060 : 0.040)
                : Color.black.opacity(isKeyWindow ? 0.030 : 0.020)
        }
        return Color.clear
    }

    private var rowStroke: Color {
        let isKeyWindow = controlActiveState == .key
        if isSelected {
            return Color.accentColor.opacity(colorScheme == .dark ? (isKeyWindow ? 0.36 : 0.26) : (isKeyWindow ? 0.28 : 0.20))
        }
        if isCurrent {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.24 : 0.14)
        }
        if isHovered {
            return colorScheme == .dark
                ? Color.white.opacity(isKeyWindow ? 0.10 : 0.07)
                : Color.black.opacity(isKeyWindow ? 0.055 : 0.038)
        }
        return .clear
    }

    init(
        isRead: Bool,
        progress: Double = 0,
        isCurrent: Bool = false,
        isSelected: Bool = false,
        label: Label? = nil,
        onToggleRead: (() -> Void)? = nil,
        onTap: @escaping () -> Void,

        @ViewBuilder content: @escaping (Bool, Label?) -> Content
    ) {
        self.isRead = isRead
        self.progress = progress
        self.isCurrent = isCurrent
        self.isSelected = isSelected
        self.label = label
        self.onToggleRead = onToggleRead
        self.onTap = onTap
        self.content = content
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 4) {
                // Clickable read/unread indicator
                let labelColor = label?.color.swiftUIColor
                let indicatorTint = (labelDisplayMode == .coloredDot ? labelColor : nil) ?? Color.accentColor
                let indicatorTrack = (labelDisplayMode == .coloredDot ? labelColor?.opacity(0.35) : nil) ?? Color.secondary.opacity(0.35)
                if let toggle = onToggleRead {
                    Button(action: toggle) {
                        ReadProgressIndicator(
                            progress: progress,
                            isRead: isRead,
                            tint: indicatorTint,
                            trackColor: indicatorTrack
                        )
                        .frame(width: 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .help(isRead ? "Mark as unread" : "Mark as read")
                    .padding(.top, 10)
                    .padding(.leading, 4)
                } else {
                    // Non-interactive indicator
                    ReadProgressIndicator(
                        progress: progress,
                        isRead: isRead,
                        tint: indicatorTint,
                        trackColor: indicatorTrack
                    )
                    .frame(width: 8, height: 8)
                        .padding(.top, 10)
                        .padding(.leading, 4)
                }

                // Pass label if mode is rowHighlight (repurposed for "Label Tag" mode)
                let labelToDisplay = (labelDisplayMode == .rowHighlight) ? label : nil
                content(isHovered, labelToDisplay)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .opacity(isRead ? 0.76 : 1.0)
            .background {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(rowFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                            .strokeBorder(rowStroke, lineWidth: 0.75)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            guard hovering != isHovered else { return }
            isHovered = hovering
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Open article")
    }
}

/// Row for displaying an article in a list
/// TODO: Add title wrapping toggle to Settings page
struct ArticleRow: View {
    let article: Article
    var extract: String? = nil  // Optional longer preview text
    var allowsEstimatedWordCount: Bool = true
    var isHovered: Bool = false
    var label: Label? = nil
    var onLabelClick: ((Label) -> Void)? = nil
    var tags: [Tag] = []
    var selectedTagId: UUID? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    private let subheadLineLimit = 2

    /// Formatted word count based on extract length
    private var wordCountText: String? {
        if let wc = article.wordCount {
            let formatted = NumberFormatter.localizedString(from: NSNumber(value: wc), number: .decimal)
            return "\(formatted) words"
        }
        guard allowsEstimatedWordCount else { return nil }
        guard let extract = extract, extract.count > 50 else { return nil }
        // Rough estimate: ~5 chars per word
        let count = extract.count / 5
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return "\(formatted) words"
    }

    private var hasFooterMetadata: Bool {
        wordCountText != nil || label != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Title
            Text(article.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            // Description
            HStack(spacing: 6) {
                Text(article.description ?? " ")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(article.description != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            // Extract preview - always reserve 2 lines of space
            Text(extract ?? " \n ")
                .font(.system(size: 11))
                .foregroundStyle(extract != nil ? AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)
            
            // Footer metadata line has a reserved height so async updates don't change row size.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(.system(size: 10))
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)))

                    if let label = label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(label.color.swiftUIColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    label.color.swiftUIColor.opacity(0.12),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(label.color.swiftUIColor.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 12, alignment: .leading)

                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            TagChipView(
                                title: tag.name,
                                isSelected: selectedTagId == tag.id,
                                showsIcon: true,
                                fixedWidth: true
                            ) {
                                onTagClick?(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, (hasFooterMetadata || !tags.isEmpty) ? 6 : 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Row that fetches its own extract if not provided
/// TODO: Add title wrapping toggle to Settings page
struct ArticleRowWithFetch: View {
    let article: Article
    var fetchSupplementalMetadata: Bool = true
    var isHovered: Bool = false
    var label: Label? = nil
    var onLabelClick: ((Label) -> Void)? = nil
    var tags: [Tag] = []
    var selectedTagId: UUID? = nil
    var trendPulse: WikipediaService.TrendPulse? = nil
    var onTrendPulseTap: ((WikipediaService.TrendPulse) -> Void)? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    private let subheadLineLimit = 2
    @Environment(AppState.self) private var appState
    
    // Local state for fetched metadata (since AppState doesn't cache everything)
    @State private var localDescription: String?
    @State private var localExtract: String?
    @State private var localWordCount: Int?

    /// Formatted word count based on full content or extract
    private var wordCountText: String? {
        // Check local state first, then article struct
        let wc = localWordCount ?? article.wordCount
        
        if let wc = wc {
             let formatted = NumberFormatter.localizedString(from: NSNumber(value: wc), number: .decimal)
             return "\(formatted) words"
        }
        
        let extract = localExtract ?? article.extract
        guard let validExtract = extract, validExtract.count > 50 else { return nil }
        // Rough estimate: ~5 chars per word
        let count = validExtract.count / 5
        let formatted = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return "\(formatted) words"
    }

    private var displayedDescription: String {
        let text = (localDescription ?? article.description)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? " " : (text ?? " ")
    }

    private var displayedExtract: String {
        let text = (localExtract ?? article.extract)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? " \n " : (text ?? " \n ")
    }

    private var hasDescription: Bool {
        localDescription != nil || article.description != nil
    }

    private var hasExtract: Bool {
        localExtract != nil || article.extract != nil
    }

    private var hasFooterMetadata: Bool {
        wordCountText != nil || label != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Title
            Text(article.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            if let trendPulse {
                SidebarTrendPulseChip(
                    pulse: trendPulse,
                    onChartRequested: {
                        onTrendPulseTap?(trendPulse)
                    }
                )
                .padding(.top, 1)
                .padding(.bottom, 1)
            }

            // Description
            HStack(spacing: 6) {
                Text(displayedDescription)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hasDescription ? AnyShapeStyle(.secondary) : AnyShapeStyle(.clear))
                    .lineLimit(subheadLineLimit)

                Spacer(minLength: 0)
            }

            // Extract preview - always reserve 2 lines of space
            Text(displayedExtract)
                .font(.system(size: 11))
                .foregroundStyle(hasExtract ? AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)) : AnyShapeStyle(.clear))
                .lineLimit(2)

            // Footer metadata line has a reserved height so async updates don't change row size.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(wordCountText ?? " ")
                        .font(.system(size: 10))
                        .foregroundStyle(wordCountText == nil ? AnyShapeStyle(.clear) : AnyShapeStyle(Color(nsColor: .tertiaryLabelColor)))

                    if let label = label {
                        Button {
                            onLabelClick?(label)
                        } label: {
                            Text(label.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(label.color.swiftUIColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    label.color.swiftUIColor.opacity(0.12),
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(label.color.swiftUIColor.opacity(0.3), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(minHeight: 12, alignment: .leading)

                if !tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            TagChipView(
                                title: tag.name,
                                isSelected: selectedTagId == tag.id,
                                showsIcon: true,
                                fixedWidth: true
                            ) {
                                onTagClick?(tag)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, (hasFooterMetadata || !tags.isEmpty) ? 6 : 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: article.id, priority: .utility) {
            guard fetchSupplementalMetadata else { return }
            let service = WikipediaService.shared
            
            // 1. Fetch Summary if missing
            if article.description == nil || article.extract == nil {
                if let summary = try? await service.fetchSummary(article.title) {
                    await MainActor.run {
                        // Update local view state
                        self.localDescription = summary.description
                        self.localExtract = summary.extract
                        
                        // Also update AppState for valid caches
                        appState.updateArticleMetadata(
                            id: article.id,
                            description: summary.description,
                            extract: summary.extract,
                            wordCount: nil
                        )
                    }
                }
            }
            
            // 2. Fetch accurate Word Count if missing
            if article.wordCount == nil {
                if let metadata = try? await service.fetchPageMetadata(article.title) {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        // Update local view state
                        self.localWordCount = metadata.wordCount
                        
                        // Update AppState
                        appState.updateArticleMetadata(
                            id: article.id,
                            description: nil,
                            extract: nil,
                            wordCount: metadata.wordCount
                        )
                    }
                }
            }
        }
    }
}

private struct SidebarTrendPulseChip: View {
    let pulse: WikipediaService.TrendPulse
    var onChartRequested: (() -> Void)? = nil

    private var deltaFraction: Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return Double(pulse.latestViews - previous) / Double(previous)
    }

    private var trendSymbol: String {
        guard let deltaFraction else { return "chart.line.uptrend.xyaxis" }
        if deltaFraction < 0 {
            return "chart.line.downtrend.xyaxis"
        }
        return "chart.line.uptrend.xyaxis"
    }

    private var deltaText: String {
        guard let deltaFraction else { return "Views" }
        let percent = deltaFraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private var viewsText: String {
        "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    private var tint: Color {
        guard let deltaFraction else { return .secondary }
        if deltaFraction > 0 { return Color.green.opacity(0.9) }
        if deltaFraction < 0 { return Color.red.opacity(0.85) }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: trendSymbol)
                .font(.system(size: 9, weight: .semibold))
            Text(deltaText)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
            Text(viewsText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay {
            Capsule()
                .stroke(tint.opacity(0.18), lineWidth: 0.7)
        }
        .contentShape(Capsule())
        .onTapGesture {
            onChartRequested?()
        }
        .help("Views from recent daily pageviews")
    }

}

struct TrendPulsePopoverView: View {
    let title: String
    let pulse: WikipediaService.TrendPulse
    @Binding var selectedRange: ViewsPopoverTimeRange
    @State private var selectedIndex: Int?
    @State private var peakDays: [WikipediaService.PeakPageviewDay] = []
    @State private var isLoadingPeakDays = false
    @State private var hoveredRecentPointID: Int?
    @State private var hoveredPeakDayID: String?

    private enum Layout {
        static let chartHeight: CGFloat = 156
        static let chartEdgePadding: CGFloat = 10
        static let popoverWidth: CGFloat = 372
    }

    private struct TrendPoint: Identifiable {
        let id: Int
        let date: Date
        let views: Int
    }

    private var fullPoints: [TrendPoint] {
        let calendar = Calendar.current
        return pulse.points.enumerated().map { index, views in
            let date = calendar.date(byAdding: .day, value: index, to: pulse.windowStart) ?? pulse.windowStart
            return TrendPoint(id: index, date: date, views: views)
        }
    }

    /// Render a reduced chart series for long windows while preserving full
    /// resolution for hover/readout values.
    private var chartPoints: [TrendPoint] {
        downsampledTrendPoints(fullPoints, maxPoints: 220)
    }

    private var selectedPoint: TrendPoint? {
        guard let selectedIndex else { return fullPoints.last }
        return fullPoints.first(where: { $0.id == selectedIndex }) ?? fullPoints.last
    }

    private var latestViewsText: String {
        NumberFormatter.localizedString(from: NSNumber(value: pulse.latestViews), number: .decimal)
    }

    private var latestViewsCompact: String {
        abbreviatedViewCount(pulse.latestViews)
    }

    private var deltaText: String {
        guard let previous = pulse.previousViews, previous > 0 else { return "No previous-day delta" }
        let deltaFraction = Double(pulse.latestViews - previous) / Double(previous)
        let percent = deltaFraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))% vs previous day"
    }

    private var deltaBadgeText: String {
        guard let previous = pulse.previousViews, previous > 0 else { return "No delta" }
        let deltaFraction = Double(pulse.latestViews - previous) / Double(previous)
        let percent = deltaFraction * 100
        let sign = percent > 0 ? "+" : ""
        return "\(sign)\(percent.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    private var deltaTint: Color {
        guard let previous = pulse.previousViews, previous > 0 else { return .secondary }
        let deltaFraction = Double(pulse.latestViews - previous) / Double(previous)
        if deltaFraction > 0 { return Color.green.opacity(0.9) }
        if deltaFraction < 0 { return Color.red.opacity(0.85) }
        return .secondary
    }

    private var windowLabel: String {
        "\(pulse.windowStart.formatted(date: .abbreviated, time: .omitted)) - \(pulse.windowEnd.formatted(date: .abbreviated, time: .omitted))"
    }

    private var xAxisDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .week:
            return .dateTime.weekday(.abbreviated)
        case .month:
            return .dateTime.month(.abbreviated).day()
        case .quarter:
            return .dateTime.month(.abbreviated)
        case .year:
            return .dateTime.month(.abbreviated)
        case .fiveYears, .max:
            return .dateTime.year()
        }
    }

    private var xAxisTickDates: [Date] {
        switch selectedRange {
        case .week:
            return generatedAxisTickDates(component: .day, step: 2)
        case .month:
            return generatedAxisTickDates(component: .day, step: 7)
        case .quarter:
            return generatedAxisTickDates(component: .month, step: 1)
        case .year:
            return generatedAxisTickDates(component: .month, step: 2)
        case .fiveYears:
            return generatedAxisTickDates(component: .year, step: 1)
        case .max:
            return generatedAxisTickDates(component: .year, step: maxAxisYearStride)
        }
    }

    private var maxAxisYearStride: Int {
        let calendar = Calendar.current
        let yearSpan = max(1, calendar.dateComponents([.year], from: pulse.windowStart, to: pulse.windowEnd).year ?? 1)
        switch yearSpan {
        case 1...8:
            return 1
        case 9...16:
            return 2
        case 17...30:
            return 5
        default:
            return 10
        }
    }

    private func generatedAxisTickDates(component: Calendar.Component, step: Int) -> [Date] {
        guard step > 0 else { return [pulse.windowStart, pulse.windowEnd] }

        let calendar = Calendar.current
        let start = pulse.windowStart
        let end = pulse.windowEnd
        guard start < end else { return [start] }

        var ticks: [Date] = [start]
        var cursor = start
        while let next = calendar.date(byAdding: component, value: step, to: cursor), next < end {
            ticks.append(next)
            cursor = next
        }

        if !calendar.isDate(ticks.last ?? start, inSameDayAs: end) {
            ticks.append(end)
        }

        return ticks
    }

    private var recentPoints: [TrendPoint] {
        Array(fullPoints.suffix(5).reversed())
    }

    private var peakDaysTaskKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(pulse.windowEnd.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)"
    }

    private func pointIndex(matching date: Date) -> Int? {
        let calendar = Calendar.current
        return fullPoints.first(where: { calendar.isDate($0.date, inSameDayAs: date) })?.id
    }

    private func resetSelectionToLatest() {
        selectedIndex = fullPoints.last?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Views")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(selectedRange.shortLabel)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            Text(title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Picker("Range", selection: $selectedRange) {
                ForEach(ViewsPopoverTimeRange.allCases) { option in
                    Text(option.shortLabel)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latestViewsCompact)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))

                Text("views")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(deltaBadgeText)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(deltaTint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(deltaTint.opacity(0.1), in: Capsule())
            }

            Text(deltaText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(chartPoints) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Views", point.views)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.accentColor)

                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Views", point.views)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.01)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }

                    if let selectedPoint {
                        RuleMark(x: .value("Date", selectedPoint.date))
                            .foregroundStyle(Color.primary.opacity(0.16))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))

                        PointMark(
                            x: .value("Date", selectedPoint.date),
                            y: .value("Views", selectedPoint.views)
                        )
                        .symbolSize(24)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(height: Layout.chartHeight)
                .chartXScale(range: .plotDimension(startPadding: Layout.chartEdgePadding, endPadding: Layout.chartEdgePadding))
                .chartXAxis {
                    AxisMarks(values: xAxisTickDates) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.primary.opacity(0.08))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.primary.opacity(0.10))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(date.formatted(xAxisDateFormat))
                            }
                        }
                            .foregroundStyle(.secondary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                            .foregroundStyle(Color.primary.opacity(0.12))
                        AxisValueLabel {
                            if let intValue = value.as(Int.self) {
                                Text(abbreviatedViewCount(intValue))
                            } else if let doubleValue = value.as(Double.self) {
                                Text(abbreviatedViewCount(Int(doubleValue.rounded())))
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    updateSelection(location: location, proxy: proxy, geometry: geometry)
                                case .ended:
                                    selectedIndex = fullPoints.last?.id
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelection(location: value.location, proxy: proxy, geometry: geometry)
                                    }
                            )
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
                }

                Text(windowLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let selectedPoint {
                HStack {
                    Text(selectedPoint.date.formatted(date: .abbreviated, time: .omitted))
                    Spacer(minLength: 0)
                    Text("\(NumberFormatter.localizedString(from: NSNumber(value: selectedPoint.views), number: .decimal)) views")
                        .monospacedDigit()
                }
                .font(.system(size: 11.5, weight: .semibold))
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 6) {
                Text("Recent Days")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(recentPoints) { point in
                    let isHovered = hoveredRecentPointID == point.id
                    HStack(spacing: 8) {
                        Text(point.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text(abbreviatedViewCount(point.views))
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(isHovered ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 0.8)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .onHover { hovering in
                        if hovering {
                            hoveredRecentPointID = point.id
                            hoveredPeakDayID = nil
                            selectedIndex = point.id
                        } else if hoveredRecentPointID == point.id {
                            hoveredRecentPointID = nil
                            resetSelectionToLatest()
                        }
                    }
                }
            }

            if isLoadingPeakDays {
                Divider().opacity(0.45)
                AppLoadingInlineLabel(
                    text: "Loading all-time highs…",
                    tone: .accent,
                    font: .system(size: 10.5, weight: .medium)
                )
            } else if !peakDays.isEmpty {
                Divider().opacity(0.45)
                VStack(alignment: .leading, spacing: 6) {
                    Text("All-Time High Days")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(peakDays.enumerated()), id: \.offset) { index, peak in
                        let isHovered = hoveredPeakDayID == peak.id
                        HStack(spacing: 8) {
                            Text("#\(index + 1)")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .leading)
                            Text(peak.date.formatted(date: .abbreviated, time: .omitted))
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                            Text(abbreviatedViewCount(peak.views))
                                .font(.system(size: 10.5, weight: .semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(isHovered ? Color.accentColor.opacity(0.22) : Color.clear, lineWidth: 0.8)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .onHover { hovering in
                            if hovering {
                                hoveredPeakDayID = peak.id
                                hoveredRecentPointID = nil
                                if let index = pointIndex(matching: peak.date) {
                                    selectedIndex = index
                                }
                            } else if hoveredPeakDayID == peak.id {
                                hoveredPeakDayID = nil
                                resetSelectionToLatest()
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: Layout.popoverWidth)
        .task(id: peakDaysTaskKey) {
            await loadPeakDays()
        }
    }

    private func updateSelection(location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let plotRect = geometry[plotFrame]
        let xPosition = location.x - plotRect.origin.x
        guard xPosition >= 0, xPosition <= plotRect.width else { return }
        guard let hoveredDate: Date = proxy.value(atX: xPosition) else { return }

        if let nearest = fullPoints.min(by: { lhs, rhs in
            abs(lhs.date.timeIntervalSince(hoveredDate)) < abs(rhs.date.timeIntervalSince(hoveredDate))
        }) {
            selectedIndex = nearest.id
        }
    }

    private func downsampledTrendPoints(_ points: [TrendPoint], maxPoints: Int) -> [TrendPoint] {
        guard points.count > maxPoints, maxPoints >= 8 else { return points }
        guard let first = points.first, let last = points.last else { return points }

        let interior = Array(points.dropFirst().dropLast())
        guard !interior.isEmpty else { return points }

        // Keep local peaks/valleys by taking min+max inside each bucket.
        let bucketCount = Swift.max(1, (maxPoints - 2) / 2)
        let bucketSize = Swift.max(
            1,
            Int((Double(interior.count) / Double(bucketCount)).rounded(.up))
        )

        var sampled: [TrendPoint] = [first]
        sampled.reserveCapacity(maxPoints)

        var start = 0
        while start < interior.count {
            let end = Swift.min(start + bucketSize, interior.count)
            let bucket = interior[start..<end]
            if let minPoint = bucket.min(by: { $0.views < $1.views }),
               let maxPoint = bucket.max(by: { $0.views < $1.views }) {
                if minPoint.id == maxPoint.id {
                    sampled.append(minPoint)
                } else if minPoint.id < maxPoint.id {
                    sampled.append(minPoint)
                    sampled.append(maxPoint)
                } else {
                    sampled.append(maxPoint)
                    sampled.append(minPoint)
                }
            }
            start += bucketSize
        }

        sampled.append(last)

        var seen = Set<Int>()
        let dedupedSorted = sampled
            .filter { seen.insert($0.id).inserted }
            .sorted(by: { $0.id < $1.id })

        if dedupedSorted.count <= maxPoints {
            return dedupedSorted
        }

        // Safety fallback if bucket composition still exceeds the point budget.
        let stride = Swift.max(
            1,
            Int((Double(points.count - 2) / Double(maxPoints - 2)).rounded(.up))
        )
        var reduced: [TrendPoint] = [first]
        var index = 1
        while index < points.count - 1 {
            reduced.append(points[index])
            index += stride
        }
        if reduced.last?.id != last.id {
            reduced.append(last)
        }
        return Array(reduced.prefix(maxPoints))
    }

    private func loadPeakDays() async {
        isLoadingPeakDays = true
        defer { isLoadingPeakDays = false }

        do {
            let result = try await WikipediaService.shared.fetchPeakPageviewDays(
                for: title,
                endingAt: pulse.windowEnd,
                top: 5
            )
            guard !Task.isCancelled else { return }
            peakDays = result
        } catch {
            guard !Task.isCancelled else { return }
            peakDays = []
        }
    }
}

enum ViewsPopoverTimeRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365
    case fiveYears = 1825
    case max = -1

    var id: Int { rawValue }

    var shortLabel: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .fiveYears: return "5Y"
        case .max: return "Max"
        }
    }

    func requestedDays(relativeTo referenceDate: Date) -> Int {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: referenceDate)

        let resolvedStartDate: Date
        switch self {
        case .week:
            resolvedStartDate = calendar.date(byAdding: .day, value: -6, to: endDate) ?? endDate
        case .month:
            resolvedStartDate = calendar.date(byAdding: .day, value: -29, to: endDate) ?? endDate
        case .quarter:
            resolvedStartDate = calendar.date(byAdding: .day, value: -89, to: endDate) ?? endDate
        case .year:
            resolvedStartDate = calendar.date(byAdding: .year, value: -1, to: endDate) ?? endDate
        case .fiveYears:
            resolvedStartDate = calendar.date(byAdding: .year, value: -5, to: endDate) ?? endDate
        case .max:
            resolvedStartDate = calendar.date(from: DateComponents(year: 2015, month: 7, day: 1)) ?? endDate
        }

        let daySpan = (calendar.dateComponents([.day], from: resolvedStartDate, to: endDate).day ?? 0) + 1
        return Swift.max(3, daySpan)
    }

    static func matching(days: Int) -> ViewsPopoverTimeRange {
        if days <= 7 { return .week }
        if days <= 30 { return .month }
        if days <= 90 { return .quarter }
        if days <= 366 { return .year }
        if days <= 1827 { return .fiveYears }
        return .max
    }
}

func abbreviatedViewCount(_ value: Int) -> String {
    let absValue = abs(Double(value))
    let sign = value < 0 ? "-" : ""

    if absValue >= 1_000_000_000 {
        return "\(sign)\((absValue / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1))))B"
    }
    if absValue >= 1_000_000 {
        return "\(sign)\((absValue / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M"
    }
    if absValue >= 1_000 {
        return "\(sign)\((absValue / 1_000).formatted(.number.precision(.fractionLength(0...1))))K"
    }
    return "\(value)"
}

private struct SidebarPageViewsPopoverPayload {
    let rowKey: String
    let title: String
    let initialPulse: WikipediaService.TrendPulse?
    let referenceDate: Date
}

struct SidebarPageViewsPopoverContent: View {
    let title: String
    let referenceDate: Date
    let initialPulse: WikipediaService.TrendPulse?

    @State private var pulse: WikipediaService.TrendPulse?
    @State private var isLoading = false
    @State private var didFailLoad = false
    @State private var selectedRange: ViewsPopoverTimeRange

    init(
        title: String,
        referenceDate: Date,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        self.title = title
        self.referenceDate = referenceDate
        self.initialPulse = initialPulse
        _pulse = State(initialValue: initialPulse)
        _selectedRange = State(initialValue: ViewsPopoverTimeRange.matching(days: initialPulse?.points.count ?? 30))
    }

    private var requestedDays: Int {
        selectedRange.requestedDays(relativeTo: referenceDate)
    }

    private var loadKey: String {
        let normalizedTitle = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let endStamp = Int(referenceDate.timeIntervalSinceReferenceDate)
        return "\(normalizedTitle)|\(endStamp)|\(selectedRange.rawValue)|\(requestedDays)"
    }

    var body: some View {
        Group {
            if let pulse {
                TrendPulsePopoverView(title: title, pulse: pulse, selectedRange: $selectedRange)
            } else if isLoading {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    AppLoadingInlineLabel(
                        text: "Loading page views…",
                        tone: .accent,
                        font: .system(size: 12, weight: .medium)
                    )
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Views")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(2)
                    Text(didFailLoad ? "Page views are unavailable for this article right now." : "No pageview data yet.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task {
                            await loadPulse()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 300, alignment: .leading)
            }
        }
        .task(id: loadKey) {
            await loadPulseIfNeeded()
        }
    }

    @MainActor
    private func loadPulseIfNeeded() async {
        await loadPulse()
    }

    @MainActor
    private func loadPulse() async {
        isLoading = true
        didFailLoad = false
        defer { isLoading = false }

        do {
            let fetched = try await WikipediaService.shared.fetchTrendPulse(
                for: title,
                referenceDate: referenceDate,
                days: requestedDays
            )
            guard !Task.isCancelled else { return }
            pulse = fetched
        } catch {
            guard !Task.isCancelled else { return }
            didFailLoad = true
        }
    }
}

private struct SavedArticleRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    let savedArticle: SavedArticle
    let isRead: Bool
    let readProgress: Double
    var isCurrent: Bool = false
    let list: ReadingList?
    let allLists: [ReadingList]
    let allLabels: [Label]
    
    let onToggleRead: () -> Void
    let onMove: (ReadingList) -> Void

    let onRemove: (() -> Void)?
    var onLabelClick: ((Label) -> Void)? = nil
    var tags: [Tag] = []
    var allTags: [Tag] = []
    var selectedTagId: UUID? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    var isSelected: Bool = false
    var onOpenArticle: ((Article) -> Void)? = nil
    let onNewLabel: (SavedArticle) -> Void
    var onNewTag: ((Article) -> Void)? = nil
    @State private var showingPageViewsPopover = false
    
    private var currentLabel: Label? {
        allLabels.first { $0.id == savedArticle.labelId }
    }
    
    private func copyToClipboard(_ text: String) {
        _ = SystemBridge.copyText(text)
    }

    var body: some View {
        let article = Article(
            id: savedArticle.title,
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            thumbnailURL: savedArticle.thumbnailURL,
            isRead: isRead,
            wordCount: savedArticle.wordCount
        )

        ArticleListItem(
            isRead: isRead,
            progress: readProgress,
            isCurrent: isCurrent,
            isSelected: isSelected,
            label: currentLabel,
            onToggleRead: onToggleRead,
            onTap: {
                if let onOpenArticle {
                    onOpenArticle(article)
                } else {
                    if SystemBridge.isOptionPressed {
                        appState.presentOptionClickSavePrompt(for: article)
                        return
                    }
                    let newTab = SystemBridge.isCommandPressed
                    appState.openArticle(article, inNewTab: newTab)
                }
            }
        ) { isHovered, label in
             ArticleRow(
                article: article,
                extract: savedArticle.extract,
                allowsEstimatedWordCount: false,
                isHovered: isHovered,
                label: label,
                onLabelClick: onLabelClick,
                tags: tags,
                selectedTagId: selectedTagId,
                onTagClick: onTagClick
             )
        }
        .task(priority: .utility) {
            // Fetch word count if missing
            if savedArticle.wordCount == nil {
                let service = WikipediaService.shared
                if let metadata = try? await service.fetchPageMetadata(savedArticle.title) {
                    guard !Task.isCancelled else { return }
                    savedArticle.wordCount = metadata.wordCount
                    try? modelContext.save()
                }
            }
        }
        .contextMenu {
            ArticleContextMenuContent(
                title: savedArticle.title,
                description: savedArticle.articleDescription,
                extract: savedArticle.extract,
                thumbnailURL: savedArticle.thumbnailURL,
                isRead: isRead,
                currentLabelId: savedArticle.labelId,
                currentTags: tags,
                savedArticle: savedArticle,
                currentList: list,
                allLabels: allLabels,
                allTags: allTags,
                allLists: allLists,
                onToggleRead: onToggleRead,
                onSetLabel: { labelId in
                    savedArticle.labelId = labelId
                    try? modelContext.save()
                },
                onNewLabel: { onNewLabel(savedArticle) },
                onToggleTag: { tag in
                    // Get or create ArticleState for tag management
                    let urlString = ReadStateSync.urlString(for: savedArticle.title)
                    let descriptor = FetchDescriptor<ArticleState>(predicate: #Predicate { $0.articleURLString == urlString })
                    let existingState = try? modelContext.fetch(descriptor).first
                    
                    let state: ArticleState
                    if let existing = existingState {
                        state = existing
                    } else {
                        guard let url = URL(string: urlString) else { return }
                        state = ArticleState(articleTitle: savedArticle.title, articleURL: url)
                        modelContext.insert(state)
                    }
                    
                    if let index = state.tags.firstIndex(where: { $0.id == tag.id }) {
                        state.tags.remove(at: index)
                    } else {
                        state.tags.append(tag)
                    }
                    state.updatedAt = Date()
                    try? modelContext.save()
                },
                onNewTag: {
                    if let onNewTag = onNewTag {
                        onNewTag(article)
                    }
                },
                onOpenInNewTab: { appState.openArticleInNewTab(article) },
                onShowPageViews: {
                    showingPageViewsPopover = true
                },
                onMoveToList: list != nil ? { targetList in onMove(targetList) } : nil,
                onAddToList: { targetList in
                    // If this article already lives in a list, "Add" duplicates into another list.
                    // If it has no list, "Add" attaches the existing record.
                    if let sourceList = list {
                        guard sourceList.id != targetList.id else { return }

                        let normalizedTitle = ReadStateSync.normalizedTitle(savedArticle.title)
                        if targetList.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalizedTitle }) {
                            return
                        }

                        let copied = SavedArticle(
                            title: savedArticle.title,
                            description: savedArticle.articleDescription,
                            extract: savedArticle.extract,
                            thumbnailURL: savedArticle.thumbnailURL,
                            list: targetList,
                            wordCount: savedArticle.wordCount
                        )
                        copied.isRead = isRead
                        copied.labelId = savedArticle.labelId
                        targetList.articles.append(copied)
                        targetList.updatedAt = Date()
                    } else {
                        savedArticle.readingList = targetList
                        if !targetList.articles.contains(where: { $0.id == savedArticle.id }) {
                            targetList.articles.append(savedArticle)
                        }
                        targetList.updatedAt = Date()
                    }
                    try? modelContext.save()
                },
                onRemove: onRemove,
                onCopyTitle: { copyToClipboard(article.title) },
                onCopyLink: { copyToClipboard(WikipediaURLBuilder.articleURLString(forTitle: article.title)) }
            )
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            )
        }
        .draggable(savedArticle.id.uuidString) {
            SwiftUI.Label(savedArticle.title, systemImage: "doc.text")
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// Directory view for a specific label
private struct LabelArticlesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    let label: Label
    let labels: [Label]
    let allTags: [Tag]
    let allLists: [ReadingList]
    let savedArticles: [SavedArticle]
    let articleStates: [ArticleState]
    let highlights: [Highlight]
    let readFilter: DirectoryReadFilter
    let sortMode: DirectorySupplementalSortMode
    
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void
    @State private var localTagFilter: Tag? = nil
    @State private var articleIndexesSnapshot = DirectoryArticleIndexes.empty

    private var labeledArticles: [SavedArticle] {
        savedArticles.filter { $0.labelId == label.id }
    }

    private var articleIndexes: DirectoryArticleIndexes {
        articleIndexesSnapshot
    }

    private var articleIndexesFingerprint: Int {
        directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private func refreshArticleIndexesSnapshot() {
        articleIndexesSnapshot = DirectoryArticleIndexes(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private func articleState(for title: String) -> ArticleState? {
        articleIndexes.articleState(for: title)
    }

    private func cachedHighlights(for title: String) -> [Highlight] {
        articleIndexes.cachedHighlights(for: title)
    }

    private func readingProgress(for title: String) -> Double {
        articleIndexes.readingProgress(for: title, in: appState)
    }

    private func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        articleIndexes.effectiveReadState(for: title, fallback: fallback)
    }

    private func tagsForArticle(title: String) -> [Tag] {
        articleIndexes.tagsForArticle(title: title)
    }

    private func articleHasTag(_ title: String, tagId: UUID) -> Bool {
        articleIndexes.articleHasTag(title, tagId: tagId)
    }

    private var filteredArticles: [SavedArticle] {
        var scoped = labeledArticles

        if readFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.title, fallback: $0.isRead) }
        }

        if let tag = localTagFilter {
            scoped = scoped.filter { articleHasTag($0.title, tagId: tag.id) }
        }

        switch sortMode {
        case .recent:
            return scoped.sorted { $0.savedAt > $1.savedAt }
        case .title:
            return scoped.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            return scoped.sorted { $0.approximateLength > $1.approximateLength }
        }
    }

    private var currentArticleTitleNormalized: String? {
        DirectoryArticleIndexes.currentArticleTitleNormalized(in: appState)
    }

    private func toggleReadStatus(_ article: SavedArticle) {
        let current = effectiveReadState(for: article.title, fallback: article.isRead)
        let newValue = !current
        let resolvedArticle = Article(
            id: article.title,
            title: article.title,
            description: article.articleDescription,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            isRead: newValue,
            wordCount: article.wordCount
        )
        _ = ReadStateSync.applyReadState(newValue, for: resolvedArticle, in: modelContext, appState: appState)
    }

    private func removeSavedArticle(_ article: SavedArticle) {
        if let list = article.readingList,
           let index = list.articles.firstIndex(where: { $0.id == article.id }) {
            list.articles.remove(at: index)
            list.updatedAt = Date()
        } else {
            modelContext.delete(article)
        }
        try? modelContext.save()
    }
    
    var body: some View {
        Section {
            if filteredArticles.isEmpty {
                Text("No articles")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if let tag = localTagFilter {
                    HStack(spacing: 6) {
                        TagChipView(title: tag.name, isSelected: true)

                        Button {
                            localTagFilter = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(filteredArticles) { article in
                    let isRead = effectiveReadState(for: article.title, fallback: article.isRead)
                    let progress = readingProgress(for: article.title)
                    let tags = tagsForArticle(title: article.title)
                    let isCurrent = currentArticleTitleNormalized == ReadStateSync.normalizedTitle(article.title)
                    SavedArticleRow(
                        savedArticle: article,
                        isRead: isRead,
                        readProgress: progress,
                        isCurrent: isCurrent,
                        list: article.readingList,
                        allLists: allLists,
                        allLabels: labels,
                        onToggleRead: {
                            toggleReadStatus(article)
                        },
                        onMove: { targetList in
                            // Move logic (copy to new list, remove from old)
                            if let sourceList = article.readingList {
                                sourceList.articles.removeAll { $0.id == article.id }
                                sourceList.updatedAt = Date()
                            }
                            // Create new article copy in target
                            let newArticle = SavedArticle(
                                title: article.title,
                                description: article.articleDescription,
                                extract: article.extract,
                                thumbnailURL: article.thumbnailURL,
                                list: targetList
                            )
                            newArticle.isRead = article.isRead
                            newArticle.labelId = article.labelId
                            targetList.articles.append(newArticle)
                            targetList.updatedAt = Date()
                            
                            modelContext.delete(article)
                            try? modelContext.save()
                        },
                        onRemove: { removeSavedArticle(article) },
                        tags: tags,
                        allTags: allTags,
                        selectedTagId: localTagFilter?.id,
                        onTagClick: { tag in
                            localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                        },
                        onNewLabel: { article in
                            onNewLabelWithArticle(article)
                        },
                        onNewTag: { article in
                            onNewTagWithArticle(article)
                        }
                    )
                }
            }
        }
        .onAppear {
            refreshArticleIndexesSnapshot()
        }
        .onChange(of: articleIndexesFingerprint) { _, _ in
            refreshArticleIndexesSnapshot()
        }
    }

}

private struct TagArticlesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    let tag: Tag
    let allTags: [Tag]
    let allLists: [ReadingList]
    let allLabels: [Label]
    let savedArticles: [SavedArticle]
    let articleStates: [ArticleState]
    let allHighlights: [Highlight]
    let readFilter: DirectoryReadFilter
    let sortMode: DirectorySupplementalSortMode
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void
    @State private var localTagFilter: Tag? = nil
    @State private var articleIndexesSnapshot = DirectoryArticleIndexes.empty
    @State private var activePageViewsArticleTitle: String?

    private var articleIndexes: DirectoryArticleIndexes {
        articleIndexesSnapshot
    }

    private var articleIndexesFingerprint: Int {
        directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: allHighlights,
            savedArticles: savedArticles
        )
    }

    private func refreshArticleIndexesSnapshot() {
        articleIndexesSnapshot = DirectoryArticleIndexes(
            articleStates: articleStates,
            highlights: allHighlights,
            savedArticles: savedArticles
        )
    }

    private func articleState(for title: String) -> ArticleState? {
        articleIndexes.articleState(for: title)
    }

    private func cachedHighlights(for title: String) -> [Highlight] {
        articleIndexes.cachedHighlights(for: title)
    }

    private func savedArticle(for title: String) -> SavedArticle? {
        articleIndexes.savedArticle(for: title)
    }

    private var taggedArticles: [Article] {
        var latestByTitle: [String: Date] = [:]
        for highlight in allHighlights {
            guard highlight.tags.contains(where: { $0.id == tag.id }) else { continue }
            let title = highlight.articleTitle
            if let existing = latestByTitle[title] {
                if highlight.createdAt > existing {
                    latestByTitle[title] = highlight.createdAt
                }
            } else {
                latestByTitle[title] = highlight.createdAt
            }
        }

        for state in articleStates {
            guard state.tags.contains(where: { $0.id == tag.id }) else { continue }
            let title = state.articleTitle
            if let existing = latestByTitle[title] {
                if state.updatedAt > existing {
                    latestByTitle[title] = state.updatedAt
                }
            } else {
                latestByTitle[title] = state.updatedAt
            }
        }

        let sortedTitles = latestByTitle
            .sorted { $0.value > $1.value }
            .map { $0.key }

        return sortedTitles.map { title in
            if let saved = savedArticle(for: title) {
                let article = Article(
                    id: saved.title,
                    title: saved.title,
                    description: saved.articleDescription,
                    extract: saved.extract,
                    thumbnailURL: saved.thumbnailURL,
                    wordCount: saved.wordCount
                )
                // Note: Article struct doesn't have readingList reference, but UI handles context separately
                return article
            }
            
            // Fallback for unsaved article (just history/highlight)
            let article = Article(id: title, title: title)
            return article
        }
    }

    private func readingProgress(for title: String) -> Double {
        articleIndexes.readingProgress(for: title, in: appState)
    }

    private func effectiveReadState(for title: String) -> Bool {
        articleIndexes.effectiveReadState(for: title, fallback: false)
    }

    private func tagsForArticle(title: String) -> [Tag] {
        articleIndexes.tagsForArticle(title: title)
    }

    private func articleHasTag(_ title: String, tagId: UUID) -> Bool {
        articleIndexes.articleHasTag(title, tagId: tagId)
    }

    private var filteredTaggedArticles: [Article] {
        var scoped = taggedArticles

        if readFilter == .unread {
            scoped = scoped.filter { !effectiveReadState(for: $0.title) }
        }

        if let filter = localTagFilter {
            scoped = scoped.filter { articleHasTag($0.title, tagId: filter.id) }
        }

        switch sortMode {
        case .recent:
            return scoped
        case .title:
            return scoped.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            return scoped.sorted { ($0.wordCount ?? 0) > ($1.wordCount ?? 0) }
        }
    }

    private var currentArticleTitleNormalized: String? {
        DirectoryArticleIndexes.currentArticleTitleNormalized(in: appState)
    }

    private func isCurrentArticle(_ title: String) -> Bool {
        currentArticleTitleNormalized == ReadStateSync.normalizedTitle(title)
    }

    private func pageViewsPopoverBinding(for articleTitle: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsArticleTitle == articleTitle },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsArticleTitle == articleTitle {
                    activePageViewsArticleTitle = nil
                }
            }
        )
    }

    var body: some View {
        Section {
            if filteredTaggedArticles.isEmpty {
                Text("No tagged articles")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if let tag = localTagFilter {
                    HStack(spacing: 6) {
                        TagChipView(title: tag.name, isSelected: true)

                        Button {
                            localTagFilter = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                ForEach(filteredTaggedArticles) { article in
                    let isRead = effectiveReadState(for: article.title)
                    let progress = readingProgress(for: article.title)
                    let tags = tagsForArticle(title: article.title)
                    
                    if let saved = savedArticle(for: article.title) {
                        SavedArticleRow(
                            savedArticle: saved,
                            isRead: isRead,
                            readProgress: progress,
                            isCurrent: isCurrentArticle(article.title),
                            list: saved.readingList,
                            allLists: allLists,
                            allLabels: allLabels,
                            onToggleRead: {
                                // Toggle read status logic
                                let newValue = !isRead
                                _ = ReadStateSync.applyReadState(newValue, for: article, in: modelContext, appState: appState)
                            },
                            onMove: { targetList in
                                // Move logic: update list reference
                                if let oldList = saved.readingList {
                                    oldList.articles.removeAll { $0.id == saved.id }
                                }
                                saved.readingList = targetList
                                targetList.articles.append(saved)
                                saved.savedAt = Date()
                                try? modelContext.save()
                            },
                            onRemove: {
                                if let list = saved.readingList {
                                    list.articles.removeAll { $0.id == saved.id }
                                    list.updatedAt = Date()
                                } else {
                                    modelContext.delete(saved)
                                }
                                try? modelContext.save()
                            },
                            tags: tags,
                            allTags: allTags,
                            selectedTagId: localTagFilter?.id,
                            onTagClick: { tag in
                                localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                            },
                            onNewLabel: { article in
                                onNewLabelWithArticle(article)
                            },
                            onNewTag: { article in
                                onNewTagWithArticle(article)
                            }
                        )
                    } else {
                        // Unsaved article (History/Highlight only)
                        ArticleListItem(
                            isRead: isRead,
                            progress: progress,
                            isCurrent: isCurrentArticle(article.title),
                            onTap: {
                                if SystemBridge.isOptionPressed {
                                    appState.presentOptionClickSavePrompt(for: article)
                                    return
                                }
                                let newTab = SystemBridge.isCommandPressed
                                appState.openArticle(article, inNewTab: newTab)
                            }
                        ) { isHovered, _ in
                            ArticleRowWithFetch(
                                article: article,
                                isHovered: isHovered,
                                tags: tags,
                                selectedTagId: localTagFilter?.id,
                                onTagClick: { tag in
                                    localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                                }
                            )
                        }
                        .contextMenu {
                            ArticleContextMenuContent(
                                article: article,
                                isRead: isRead,
                                currentTags: tags,
                                allLabels: allLabels,
                                allTags: allTags,
                                allLists: allLists,
                                modelContext: modelContext,
                                appState: appState,
                                onNewLabel: { draft in
                                    onNewLabelWithArticle(draft)
                                },
                                onNewTag: { draftArticle in
                                    onNewTagWithArticle(draftArticle)
                                },
                                onShowPageViews: {
                                    activePageViewsArticleTitle = article.title
                                }
                            )
                        }
                        .popover(isPresented: pageViewsPopoverBinding(for: article.title), arrowEdge: .trailing) {
                            SidebarPageViewsPopoverContent(
                                title: article.title,
                                referenceDate: Date()
                            )
                        }
                    }
                }
            }
        }
        .onAppear {
            refreshArticleIndexesSnapshot()
        }
        .onChange(of: articleIndexesFingerprint) { _, _ in
            refreshArticleIndexesSnapshot()
        }
    }
}

extension DirectoryView {
    private var canStepDiscoverDateForward: Bool {
        discoverReferenceDate < Calendar.current.startOfDay(for: Date())
    }

    private var timeMachineAccentPrimary: Color {
        Color(nsColor: .systemPurple)
    }

    private var timeMachineAccentSecondary: Color {
        Color(nsColor: .systemIndigo)
    }

    private var timeMachineControlFillColor: Color {
        timeMachineAccentPrimary.opacity(colorScheme == .dark ? 0.22 : 0.13)
    }

    private var timeMachineControlStrokeColor: Color {
        timeMachineAccentSecondary.opacity(colorScheme == .dark ? 0.34 : 0.20)
    }

    private static let sidebarTimeTravelSkeletonDelayNanoseconds: UInt64 = 1_600_000_000

    private func updateSidebarTimeTravelSkeletonVisibility() {
        sidebarTimeTravelSkeletonDelayTask?.cancel()
        sidebarTimeTravelSkeletonDelayTask = nil

        guard shouldQueueSidebarTimeTravelSkeleton else {
            if shouldShowDelayedSidebarTimeTravelSkeleton {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    shouldShowDelayedSidebarTimeTravelSkeleton = false
                }
            } else {
                shouldShowDelayedSidebarTimeTravelSkeleton = false
            }
            return
        }

        guard !shouldShowDelayedSidebarTimeTravelSkeleton else { return }
        sidebarTimeTravelSkeletonDelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.sidebarTimeTravelSkeletonDelayNanoseconds)
            guard !Task.isCancelled else { return }
            guard shouldQueueSidebarTimeTravelSkeleton else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                shouldShowDelayedSidebarTimeTravelSkeleton = true
            }
        }
    }

    private func queueDiscoverLoadDebounced(
        forceRefresh: Bool = false,
        delayNanoseconds: UInt64 = 0
    ) {
        discoverDateLoadTask?.cancel()
        let targetReferenceDate = discoverReferenceDate
        discoverDateLoadTask = Task { @MainActor in
            if !forceRefresh, delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
                guard !Task.isCancelled else { return }
            }
            discoverFeedStore.queueLoad(referenceDate: targetReferenceDate, forceRefresh: forceRefresh)
        }
    }

    private func shiftDiscoverDate(days: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .day, value: days, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    private func shiftDiscoverDate(years: Int) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let shifted = calendar.date(byAdding: .year, value: years, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    private var discoverTimeMachineCompactDateLabel: String {
        Self.timeMachineCompactDateFormatter.string(from: discoverReferenceDate)
    }

    private var discoverTimeMachineHeaderDateLabel: String {
        Self.timeMachineHeaderDateFormatter.string(from: discoverReferenceDate)
    }

    private var discoverTimeMachineLongDateLabel: String {
        Self.timeMachineLongDateFormatter.string(from: discoverReferenceDate)
    }

    private var discoverTimeMachineMediumDateLabel: String {
        Self.timeMachineMediumDateFormatter.string(from: discoverReferenceDate)
    }

    private var isDiscoverDateToday: Bool {
        Calendar.current.isDate(discoverReferenceDate, inSameDayAs: Date())
    }

    private static let timeMachineCompactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()

    private static let timeMachineHeaderDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        return formatter
    }()

    private static let timeMachineLongDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMMM d, yyyy")
        return formatter
    }()

    private static let timeMachineMediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy")
        return formatter
    }()

    private enum SidebarTimeMachineQuickShortcut: Hashable {
        case today
        case yesterday
        case week
        case month
        case year
        case fiveYears

        var title: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .week: return "7D"
            case .month: return "30D"
            case .year: return "1Y"
            case .fiveYears: return "5Y"
            }
        }

        /// Conservative width estimate (button content + horizontal chrome)
        /// used to choose a guaranteed-fit shortcut subset.
        var estimatedWidth: CGFloat {
            switch self {
            case .today: return 52
            case .yesterday: return 76
            case .week: return 40
            case .month: return 44
            case .year: return 40
            case .fiveYears: return 40
            }
        }
    }

    @ViewBuilder
    private func timeMachineStepButton(
        _ symbol: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9.5, weight: .semibold))
                .frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .foregroundStyle(.primary.opacity(disabled ? 0.36 : 0.86))
        .background(timeMachineControlFillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(timeMachineControlStrokeColor, lineWidth: 0.6)
        )
    }

    @ViewBuilder
    private var timeMachineTemporalLensButton: some View {
        Button {
            isTimeMachineDatePickerPresented.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 9.5, weight: .semibold))

                ViewThatFits(in: .horizontal) {
                    Text(discoverTimeMachineLongDateLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(discoverTimeMachineMediumDateLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)

                    Text(discoverTimeMachineCompactDateLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 20)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.88))
        .background(timeMachineControlFillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(timeMachineControlStrokeColor, lineWidth: 0.6)
        )
        .popover(isPresented: $isTimeMachineDatePickerPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                DatePicker(
                    "Jump to date",
                    selection: $selectedDiscoverDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .labelsHidden()

                HStack(spacing: 8) {
                    Button("Today") {
                        selectedDiscoverDate = Date()
                    }
                    .disabled(isDiscoverDateToday)

                    Spacer(minLength: 0)

                    Button("Done") {
                        isTimeMachineDatePickerPresented = false
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
            }
            .padding(10)
            .frame(width: 250)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if let lastX = timeMachineLensLastDragX {
                        stepTimeMachineLensByDrag(deltaX: value.location.x - lastX)
                    }
                    timeMachineLensLastDragX = value.location.x
                }
                .onEnded { _ in
                    resetTimeMachineLensDrag()
                }
        )
        .help("Temporal Lens: drag left/right to scrub days")
    }

    @ViewBuilder
    private var timeMachineSecondaryControlsRow: some View {
        GeometryReader { proxy in
            let shortcuts = visibleTimeMachineQuickShortcuts(for: proxy.size.width)

            HStack(spacing: 5) {
                ForEach(shortcuts, id: \.self) { shortcut in
                    timeMachineQuickJumpButton(shortcut.title, disabled: shortcut == .today && isDiscoverDateToday) {
                        handleTimeMachineQuickShortcut(shortcut)
                    }
                }
                Spacer(minLength: 0)
                timeMachineJumpMenuButton
                timeMachineRefreshButton
            }
            .frame(width: proxy.size.width, alignment: .leading)
        }
        .frame(height: 20)
    }

    private func visibleTimeMachineQuickShortcuts(for availableWidth: CGFloat) -> [SidebarTimeMachineQuickShortcut] {
        let candidates: [[SidebarTimeMachineQuickShortcut]] = [
            [.today, .yesterday, .week, .month, .year, .fiveYears],
            [.today, .week, .month, .year, .fiveYears],
            [.today, .week, .year],
            [.today, .week],
            [.today],
            []
        ]

        for candidate in candidates {
            if requiredWidthForQuickShortcuts(candidate) <= availableWidth {
                return candidate
            }
        }
        return []
    }

    private func requiredWidthForQuickShortcuts(_ shortcuts: [SidebarTimeMachineQuickShortcut]) -> CGFloat {
        let shortcutWidth = shortcuts.reduce(CGFloat.zero) { partial, shortcut in
            partial + shortcut.estimatedWidth
        }
        let shortcutSpacing = CGFloat(max(shortcuts.count - 1, 0)) * 5
        let trailingControlsWidth: CGFloat = 24 + 24 + 5
        return shortcutWidth + shortcutSpacing + trailingControlsWidth
    }

    private func handleTimeMachineQuickShortcut(_ shortcut: SidebarTimeMachineQuickShortcut) {
        switch shortcut {
        case .today:
            selectedDiscoverDate = Date()
        case .yesterday:
            shiftDiscoverDate(days: -1)
        case .week:
            shiftDiscoverDate(days: -7)
        case .month:
            shiftDiscoverDate(days: -30)
        case .year:
            shiftDiscoverDate(years: -1)
        case .fiveYears:
            shiftDiscoverDate(years: -5)
        }
    }

    @ViewBuilder
    private func timeMachineQuickJumpButton(
        _ title: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .frame(height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .foregroundStyle(.primary.opacity(disabled ? 0.36 : 0.86))
        .background(timeMachineAccentPrimary.opacity(colorScheme == .dark ? 0.17 : 0.11), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(timeMachineControlStrokeColor, lineWidth: 0.6)
        )
    }

    private func stepTimeMachineLensByDrag(deltaX: CGFloat) {
        timeMachineLensDragAccumulatedX += deltaX
        let threshold: CGFloat = 18

        while abs(timeMachineLensDragAccumulatedX) >= threshold {
            let isForward = timeMachineLensDragAccumulatedX > 0
            shiftDiscoverDate(days: isForward ? 1 : -1)
            timeMachineLensDragAccumulatedX += isForward ? -threshold : threshold
        }
    }

    private func resetTimeMachineLensDrag() {
        timeMachineLensLastDragX = nil
        timeMachineLensDragAccumulatedX = 0
    }

    @ViewBuilder
    private var timeMachineRefreshButton: some View {
        Button {
            queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)
        } label: {
            Image(systemName: discoverFeedStore.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(discoverFeedStore.isLoading ? 0.38 : 0.86))
        .background(timeMachineControlFillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(timeMachineControlStrokeColor, lineWidth: 0.6)
        )
        .disabled(discoverFeedStore.isLoading)
        .help("Refresh Discover")
    }

    @ViewBuilder
    private var timeMachineJumpMenuButton: some View {
        Menu {
            Button("Today", systemImage: "sun.max") {
                selectedDiscoverDate = Date()
            }
            .disabled(isDiscoverDateToday)

            Button("Yesterday", systemImage: "clock.arrow.circlepath") {
                shiftDiscoverDate(days: -1)
            }
            Button("7 days ago", systemImage: "calendar.badge.clock") {
                shiftDiscoverDate(days: -7)
            }
            Button("30 days ago", systemImage: "calendar") {
                shiftDiscoverDate(days: -30)
            }
            Button("1 year ago", systemImage: "clock.arrow.circlepath") {
                shiftDiscoverDate(years: -1)
            }
            Button("5 years ago", systemImage: "clock.arrow.2.circlepath") {
                shiftDiscoverDate(years: -5)
            }

            Divider()

            Button("Hide Time Machine", systemImage: "eye.slash") {
                withAnimation(.easeInOut(duration: 0.18)) {
                    discoverSidebarTimeMachineHidden = true
                }
            }
        } label: {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary.opacity(0.86))
        .background(timeMachineControlFillColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(timeMachineControlStrokeColor, lineWidth: 0.6)
        )
    }

    @ViewBuilder
    func discoverSections() -> some View {
        Section {
            if discoverSidebarTimeMachineHidden {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                        .background(Color.primary.opacity(0.08), in: Circle())

                    Text("Time Machine hidden")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Button("Show") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            discoverSidebarTimeMachineHidden = false
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7)
                    )
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 0.7)
                )
                .padding(.vertical, 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                            .font(.system(size: 10.5, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(timeMachineAccentPrimary.opacity(0.92))
                            .frame(width: 18, height: 18)

                        Text("Time Machine")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.90))
                            .lineLimit(1)
                            .minimumScaleFactor(0.90)
                            .layoutPriority(1)
                    }

                    HStack(spacing: 5) {
                        timeMachineStepButton("chevron.left") {
                            shiftDiscoverDate(days: -1)
                        }

                        timeMachineTemporalLensButton
                            .frame(maxWidth: .infinity, alignment: .center)
                            .layoutPriority(1)

                        timeMachineStepButton("chevron.right", disabled: !canStepDiscoverDateForward) {
                            shiftDiscoverDate(days: 1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    timeMachineSecondaryControlsRow
                    .padding(.top, 1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            LinearGradient(
                                colors: [
                                    timeMachineAccentPrimary.opacity(colorScheme == .dark ? 0.22 : 0.14),
                                    timeMachineAccentSecondary.opacity(colorScheme == .dark ? 0.14 : 0.09),
                                    .clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(timeMachineControlStrokeColor.opacity(colorScheme == .dark ? 0.75 : 0.85), lineWidth: 0.7)
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.07), radius: 4, y: 1)
                .help("Time Machine lets you see what people were reading in the past.")
                .padding(.vertical, 1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
            }
        } header: {
            Text(discoverTimeMachineHeaderDateLabel)
        }

        if discoverFeedStore.isLoading && discoverFeedStore.feed == nil {
            Section {
                AppLoadingInlineLabel(
                    text: "Loading discover feed…",
                    tone: .accent,
                    font: .subheadline.weight(.medium)
                )
                .padding(.vertical, 8)
            }
        } else if let discoverError = discoverFeedStore.errorMessage, discoverFeedStore.feed == nil {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Discover unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text(discoverError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        } else if let feed = discoverFeedStore.feed {
            let mostReadItems = discoverMostReadItems(from: feed)

            if let featured = feed.featuredArticle {
                Section("Featured Article") {
                    discoverArticleRow(featured)
                }
            }

            Section("Most Read") {
                if mostReadItems.isEmpty {
                    Text("Most Read is temporarily unavailable for this date.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(mostReadItems) { result in
                        discoverArticleRow(result, showTrendPulse: true)
                    }
                }
            }

            if !feed.newsStories.isEmpty {
                Section("News Briefing") {
                    ForEach(feed.newsStories.prefix(8)) { story in
                        DiscoverStoryRow(story: story, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }

            if !feed.inTheNews.isEmpty {
                Section("In the News") {
                    ForEach(feed.inTheNews.prefix(12)) { result in
                        discoverArticleRow(result)
                    }
                }
            }

            let primaryTimeline = feed.onThisDaySelected.isEmpty ? feed.onThisDay : feed.onThisDaySelected
            if !primaryTimeline.isEmpty {
                Section("This Day in History") {
                    ForEach(primaryTimeline.prefix(12)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }

            if !feed.onThisDayBirths.isEmpty {
                Section("Born on This Day") {
                    ForEach(feed.onThisDayBirths.prefix(8)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }

            if !feed.onThisDayDeaths.isEmpty {
                Section("Died on This Day") {
                    ForEach(feed.onThisDayDeaths.prefix(8)) { event in
                        DiscoverTimelineRow(event: event, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }

            if !feed.holidays.isEmpty {
                Section("Holidays & Observances") {
                    ForEach(feed.holidays.prefix(8)) { holiday in
                        DiscoverHolidayListRow(holiday: holiday, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }

            if !feed.didYouKnow.isEmpty {
                Section("Did You Know?") {
                    ForEach(feed.didYouKnow.prefix(8)) { fact in
                        DiscoverFactRow(fact: fact, referenceDate: discoverTrendReferenceDate) { article, inNewTab in
                            openDiscoverArticle(article, inNewTab: inNewTab)
                        }
                    }
                }
            }
        }
    }

    private func discoverArticleRow(
        _ result: WikipediaService.SearchResult,
        showTrendPulse: Bool = false
    ) -> some View {
        let article = discoverArticle(from: result)
        let titleKey = ReadStateSync.normalizedTitle(article.title)
        let rowKey = "discover:\(result.id):\(titleKey)"
        let isRead = effectiveReadState(for: article.title, fallback: article.isRead)
        let progress = readingProgress(for: article.title)
        let tags = tagsForArticle(title: article.title)
        let trendPulse = showTrendPulse ? discoverTrendPulseStore.pulse(for: article.title) : nil

        return ArticleListItem(
            isRead: isRead,
            progress: progress,
            isCurrent: isCurrentArticle(article.title),
            onTap: {
                if pendingPageViewsRowKey == rowKey {
                    pendingPageViewsRowKey = nil
                    return
                }
                openDiscoverArticle(result, inNewTab: nil)
            }
        ) { isHovered, label in
            ArticleRowWithFetch(
                article: article,
                isHovered: isHovered,
                label: label,
                tags: tags,
                selectedTagId: localTagFilter?.id,
                trendPulse: trendPulse,
                onTrendPulseTap: { pulse in
                    pendingPageViewsRowKey = rowKey
                    presentPageViewsPopover(
                        for: article.title,
                        rowKey: rowKey,
                        initialPulse: pulse,
                        referenceDate: discoverTrendReferenceDate
                    )
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 700_000_000)
                        if pendingPageViewsRowKey == rowKey {
                            pendingPageViewsRowKey = nil
                        }
                    }
                },
                onTagClick: { tag in
                    localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                }
            )
        }
        .contextMenu {
            ArticleContextMenuContent(
                article: article,
                isRead: isRead,
                currentTags: tags,
                allLabels: labels,
                allTags: self.tags,
                allLists: allLists,
                modelContext: modelContext,
                appState: appState,
                onNewLabel: { draft in
                    onNewLabelWithArticle(draft)
                },
                onNewTag: { draftArticle in
                    onNewTagWithArticle(draftArticle)
                },
                onShowPageViews: {
                    presentPageViewsPopover(
                        for: article.title,
                        rowKey: rowKey,
                        initialPulse: trendPulse,
                        referenceDate: discoverTrendReferenceDate
                    )
                }
            )
        }
        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
            pageViewsPopover(for: rowKey)
        }
    }

    private func discoverArticle(from result: WikipediaService.SearchResult) -> Article {
        Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
    }

    private func openDiscoverArticle(_ result: WikipediaService.SearchResult, inNewTab: Bool?) {
        let article = discoverArticle(from: result)
        let shouldOpenInNewTab = inNewTab ?? SystemBridge.isCommandPressed
        openArticleFromPrimaryClick(article, inNewTab: shouldOpenInNewTab)
    }

    @ViewBuilder
    func tabHistorySection(tab: ArticleTab) -> some View {
        Section {
            if tab.history.isEmpty {
                Text("No history")
                    .foregroundStyle(.secondary)
            } else {
                let filteredHistory = filteredTabHistoryItems(for: tab)
                if let tag = localTagFilter {
                    tagFilterRow(tag: tag)
                }
                ForEach(filteredHistory, id: \.id) { item in
                    let rowKey = "history:\(tab.id.uuidString):\(item.id)"
                    let isCurrent = tab.history.indices.contains(tab.currentIndex) &&
                                   tab.history[tab.currentIndex].article.title == item.article.title
                    let isRead = effectiveReadState(for: item.article.title, fallback: item.article.isRead)
                    let progress = readingProgress(for: item.article.title)
                    let tags = tagsForArticle(title: item.article.title)
                    
                    // Uses regular logic for History (unsaved check logic could be added here later for parity if requested)
                    ArticleListItem(
                        isRead: isRead,
                        progress: progress,
                        isCurrent: isCurrent,
                        onTap: {
                            let newTab = SystemBridge.isCommandPressed
                            openArticleFromPrimaryClick(item.article, inNewTab: newTab)
                        }
                    ) { isHovered, label in
                        ArticleRowWithFetch(
                            article: item.article,
                            isHovered: isHovered,
                            label: label,
                            tags: tags,
                            selectedTagId: localTagFilter?.id,
                            onTagClick: { tag in
                                localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                            }
                        )
                    }
                    .contextMenu {
                        ArticleContextMenuContent(
                            article: item.article,
                            isRead: isRead,
                            currentTags: tags,
                            allLabels: labels,
                            allTags: self.tags,
                            allLists: allLists,
                            modelContext: modelContext,
                            appState: appState,
                            onNewLabel: { draft in
                                onNewLabelWithArticle(draft)
                            },
                            onNewTag: { draftArticle in
                                onNewTagWithArticle(draftArticle)
                            },
                            onShowPageViews: {
                                presentPageViewsPopover(for: item.article.title, rowKey: rowKey)
                            }
                        )
                    }
                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                        pageViewsPopover(for: rowKey)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func recentArticlesSection() -> some View {
        Section {
            let filteredRecents = filteredRecentArticles()
            if let tag = localTagFilter {
                tagFilterRow(tag: tag)
            }
            ForEach(filteredRecents) { article in
                let isRead = effectiveReadState(for: article.title, fallback: article.isRead)
                let progress = readingProgress(for: article.title)
                let tags = tagsForArticle(title: article.title)

                if let saved = savedArticle(for: article.title) {
                    SavedArticleRow(
                        savedArticle: saved,
                        isRead: isRead,
                        readProgress: progress,
                        isCurrent: isCurrentArticle(article.title),
                        list: saved.readingList,
                        allLists: allLists,
                        allLabels: labels,
                        onToggleRead: {
                            toggleReadStatus(saved)
                        },
                        onMove: { target in moveArticle(saved, from: saved.readingList, to: target) },
                        onRemove: { appState.removeFromRecent(article) },
                        onLabelClick: { label in
                            localLabelFilter = label
                        },
                        tags: tags,
                        allTags: self.tags,
                        selectedTagId: localTagFilter?.id,
                        onTagClick: { tag in
                            localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                        },
                        onNewLabel: { article in
                            onNewLabelWithArticle(article)
                        },
                        onNewTag: { article in
                            onNewTagWithArticle(article)
                        }
                    )
                } else {
                    let rowKey = "recents-unsaved:\(article.id):\(ReadStateSync.normalizedTitle(article.title))"
                    ArticleListItem(
                        isRead: isRead,
                        progress: progress,
                        isCurrent: isCurrentArticle(article.title),
                        onTap: {
                            let newTab = SystemBridge.isCommandPressed
                            openArticleFromPrimaryClick(article, inNewTab: newTab)
                        }
                    ) { isHovered, label in
                        ArticleRowWithFetch(
                            article: article,
                            isHovered: isHovered,
                            label: label,
                            tags: tags,
                            selectedTagId: localTagFilter?.id,
                            onTagClick: { tag in
                                localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                            }
                        )
                    }
                    .contextMenu {
                        ArticleContextMenuContent(
                            article: article,
                            isRead: isRead,
                            currentTags: tags,
                            allLabels: labels,
                            allTags: self.tags,
                            allLists: allLists,
                            modelContext: modelContext,
                            appState: appState,
                            onNewLabel: { draft in
                                onNewLabelWithArticle(draft)
                            },
                            onNewTag: { draftArticle in
                                onNewTagWithArticle(draftArticle)
                            },
                            onRemove: {
                                appState.removeFromRecent(article)
                            },
                            onShowPageViews: {
                                presentPageViewsPopover(for: article.title, rowKey: rowKey)
                            }
                        )
                    }
                    .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                        pageViewsPopover(for: rowKey)
                    }
                }
            }
        }
    }
}

private struct DiscoverTimelineRow: View {
    let event: WikipediaService.DiscoverFeed.OnThisDayEvent
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void
    @State private var showingPageViewsPopover = false

    var body: some View {
        Button {
            if let article = event.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(event.article == nil)
        .contextMenu {
            if let article = event.article {
                Button {
                    onOpenArticle(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpenArticle(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(wikipediaURLString(for: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = event.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(event.year)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineSpacing(1.1)
                    .lineLimit(3)
                if let article = event.article {
                    Text(article.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverFactRow: View {
    let fact: WikipediaService.DiscoverFeed.DidYouKnowFact
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void
    @State private var showingPageViewsPopover = false

    var body: some View {
        Button {
            if let article = fact.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.text)
                        .font(.system(size: 12, weight: .medium))
                        .lineSpacing(1.1)
                        .lineLimit(3)
                    if let article = fact.article {
                        Text(article.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(fact.article == nil)
        .contextMenu {
            if let article = fact.article {
                Button {
                    onOpenArticle(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpenArticle(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(wikipediaURLString(for: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = fact.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }

    private func wikipediaURLString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}

private struct DiscoverStoryRow: View {
    let story: WikipediaService.DiscoverFeed.NewsStory
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void
    @State private var activePageViewsTitle: String?

    private var renderedStoryText: String {
        Self.sanitizedStoryText(story.story)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !story.story.isEmpty {
                Text(renderedStoryText)
                    .font(.system(size: 12, weight: .medium))
                    .lineSpacing(1.1)
                    .lineLimit(3)
            }

            if !story.links.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(story.links.prefix(4)) { article in
                        Button {
                            onOpenArticle(article, SystemBridge.isCommandPressed)
                        } label: {
                            Text(article.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onOpenArticle(article, false)
                            } label: {
                                SwiftUI.Label("Open", systemImage: "doc.text")
                            }

                            Button {
                                onOpenArticle(article, true)
                            } label: {
                                SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                            }

                            Button {
                                activePageViewsTitle = article.title
                            } label: {
                                SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                            }

                            Divider()

                            Button {
                                copyToClipboard(article.title)
                            } label: {
                                SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                            }

                            Button {
                                copyToClipboard(WikipediaURLBuilder.articleURLString(forTitle: article.title))
                            } label: {
                                SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                            }
                        }
                        .popover(
                            isPresented: Binding(
                                get: { activePageViewsTitle == article.title },
                                set: { isPresented in
                                    guard !isPresented else { return }
                                    if activePageViewsTitle == article.title {
                                        activePageViewsTitle = nil
                                    }
                                }
                            ),
                            arrowEdge: .trailing
                        ) {
                            if activePageViewsTitle == article.title {
                                SidebarPageViewsPopoverContent(
                                    title: article.title,
                                    referenceDate: referenceDate
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    private static func sanitizedStoryText(_ storyText: String) -> String {
        let raw = storyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "" }

        return stripMarkdownLinksPreservingLabels(in: raw)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Strips Markdown link wrappers (`[label](url)`) while preserving label text.
    /// Handles URLs that contain nested parentheses.
    private static func stripMarkdownLinksPreservingLabels(in text: String) -> String {
        var output = ""
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == "[" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            guard let closingBracket = text[index...].firstIndex(of: "]") else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let afterBracket = text.index(after: closingBracket)
            guard afterBracket < text.endIndex, text[afterBracket] == "(" else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            let labelStart = text.index(after: index)
            let label = text[labelStart..<closingBracket]

            var cursor = text.index(after: afterBracket)
            var depth = 1
            while cursor < text.endIndex && depth > 0 {
                switch text[cursor] {
                case "(":
                    depth += 1
                case ")":
                    depth -= 1
                default:
                    break
                }
                cursor = text.index(after: cursor)
            }

            guard depth == 0 else {
                output.append(text[index])
                index = text.index(after: index)
                continue
            }

            output.append(contentsOf: label)
            index = cursor
        }

        return output
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }
}

private struct SidebarTimeTravelSkeletonOverlay: View {
    let dateLabel: String
    let topInset: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : (1.0 / 30.0))) { context in
            let progress = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let phase: CGFloat = reduceMotion ? -1.1 : CGFloat((progress * 2) - 1)

            VStack(alignment: .leading, spacing: 10) {
                Color.clear.frame(height: topInset + 8)

                VStack(alignment: .leading, spacing: 10) {
                    SidebarTimeTravelSkeletonHeader(
                        dateLabel: dateLabel,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )

                    SidebarTimeTravelSkeletonSection(
                        titleWidth: 74,
                        rowRange: 0..<4,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )

                    SidebarTimeTravelSkeletonSection(
                        titleWidth: 102,
                        rowRange: 4..<7,
                        shimmerPhase: phase,
                        shimmerEnabled: !reduceMotion
                    )
                }
                .padding(.horizontal, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background {
                SidebarPaneBackground()
                    .overlay {
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.07 : 0.04),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

private struct SidebarTimeTravelSkeletonHeader: View {
    let dateLabel: String
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 10.5, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color(nsColor: .systemPurple).opacity(0.90))
                    .frame(width: 18, height: 18)
                    .background(
                        Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.16 : 0.10),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                Text("Time Machine")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.88))

                Spacer(minLength: 0)

                Text("SCANNING")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(nsColor: .systemPurple).opacity(0.84))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.16 : 0.09))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.6)
                    )
            }

            HStack(spacing: 5) {
                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -10
                )

                SidebarTimeTravelTargetDatePill(dateLabel: dateLabel)

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: 10
                )
            }

            HStack(spacing: 6) {
                SidebarTimeTravelSkeletonChip(width: 40, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)
                SidebarTimeTravelSkeletonChip(width: 56, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)
                SidebarTimeTravelSkeletonChip(width: 44, shimmerPhase: shimmerPhase, shimmerEnabled: shimmerEnabled)

                Spacer(minLength: 0)

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -8
                )

                SidebarTimeTravelSkeletonBar(
                    width: 22,
                    height: 22,
                    cornerRadius: 6,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: 8
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.12 : 0.07),
                            Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.06 : 0.03),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.7)
        )
        .overlay {
            SidebarGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.030 : 0.020)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .blendMode(.screen)
                .opacity(reduceMotion ? 0.08 : 0.16)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.05), radius: 3, y: 1)
    }
}

private struct SidebarTimeTravelSkeletonSection: View {
    let titleWidth: CGFloat
    let rowRange: Range<Int>
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarTimeTravelSkeletonBar(
                width: titleWidth,
                height: 8,
                cornerRadius: 4,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: -9
            )
            .padding(.leading, 4)
            .opacity(colorScheme == .dark ? 0.88 : 0.74)

            VStack(spacing: 4) {
                ForEach(Array(rowRange), id: \.self) { index in
                    SidebarTimeTravelSkeletonRow(
                        index: index,
                        shimmerPhase: shimmerPhase,
                        shimmerEnabled: shimmerEnabled
                    )
                }
            }
        }
    }
}

private struct SidebarTimeTravelSkeletonRow: View {
    let index: Int
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var titleWidth: CGFloat {
        78 + CGFloat((index % 4) * 18)
    }

    private var subtitleWidth: CGFloat {
        126 - CGFloat((index % 3) * 14)
    }

    private var trailingWidth: CGFloat {
        28 + CGFloat((index % 3) * 10)
    }

    var body: some View {
        HStack(spacing: 8) {
            SidebarTimeTravelSkeletonBar(
                width: 22,
                height: 22,
                cornerRadius: 6,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: -12
            )

            VStack(alignment: .leading, spacing: 5) {
                SidebarTimeTravelSkeletonBar(
                    width: titleWidth,
                    height: 9,
                    cornerRadius: 4,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled
                )

                SidebarTimeTravelSkeletonBar(
                    width: subtitleWidth,
                    height: 7.5,
                    cornerRadius: 3.5,
                    shimmerPhase: shimmerPhase,
                    shimmerEnabled: shimmerEnabled,
                    tiltDegrees: -8
                )
            }

            Spacer(minLength: 0)

            SidebarTimeTravelSkeletonBar(
                width: trailingWidth,
                height: 7.5,
                cornerRadius: 3.5,
                shimmerPhase: shimmerPhase,
                shimmerEnabled: shimmerEnabled,
                tiltDegrees: 9
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07), lineWidth: 0.6)
        )
    }
}

private struct SidebarTimeTravelSkeletonChip: View {
    let width: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool

    var body: some View {
        SidebarTimeTravelSkeletonBar(
            width: width,
            height: 18,
            cornerRadius: 9,
            shimmerPhase: shimmerPhase,
            shimmerEnabled: shimmerEnabled,
            tiltDegrees: -7
        )
    }
}

private struct SidebarTimeTravelTargetDatePill: View {
    let dateLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(dateLabel)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary.opacity(0.84))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.14 : 0.07),
                                Color(nsColor: .systemIndigo).opacity(colorScheme == .dark ? 0.07 : 0.03),
                                .clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.6)
            )
            .overlay {
                SidebarGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.025 : 0.016)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .blendMode(.screen)
                    .opacity(reduceMotion ? 0.06 : 0.12)
            }
    }
}

private struct SidebarTimeTravelSkeletonBar: View {
    let width: CGFloat?
    let height: CGFloat
    let cornerRadius: CGFloat
    let shimmerPhase: CGFloat
    let shimmerEnabled: Bool
    var tiltDegrees: Double = 12

    @Environment(\.colorScheme) private var colorScheme

    private var baseGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.08),
                Color(nsColor: .systemPurple).opacity(colorScheme == .dark ? 0.10 : 0.05),
                Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(baseGradient)
            .overlay {
                if shimmerEnabled {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        .clear,
                                        Color.white.opacity(colorScheme == .dark ? 0.26 : 0.48),
                                        .clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .rotationEffect(.degrees(tiltDegrees))
                            .offset(x: shimmerPhase * max(proxy.size.width, 1))
                    }
                    .clipped()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.05 : 0.10), lineWidth: 0.5)
            )
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }
}

private struct SidebarGlitchScanlineOverlay: View {
    let lineOpacity: Double

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                var y: CGFloat = 0
                while y < proxy.size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    y += 3
                }
            }
            .stroke(Color.white.opacity(lineOpacity), lineWidth: 0.42)
        }
        .allowsHitTesting(false)
    }
}

private struct DiscoverHolidayListRow: View {
    let holiday: WikipediaService.DiscoverFeed.HolidayItem
    let referenceDate: Date
    let onOpenArticle: (WikipediaService.SearchResult, Bool) -> Void
    @State private var showingPageViewsPopover = false

    var body: some View {
        Button {
            if let article = holiday.article {
                onOpenArticle(article, SystemBridge.isCommandPressed)
            }
        } label: {
            rowContent
        }
        .buttonStyle(.plain)
        .disabled(holiday.article == nil)
        .contextMenu {
            if let article = holiday.article {
                Button {
                    onOpenArticle(article, false)
                } label: {
                    SwiftUI.Label("Open", systemImage: "doc.text")
                }

                Button {
                    onOpenArticle(article, true)
                } label: {
                    SwiftUI.Label("Open in New Tab", systemImage: "plus.rectangle.on.rectangle")
                }

                Button {
                    showingPageViewsPopover = true
                } label: {
                    SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                }

                Divider()

                Button {
                    copyToClipboard(article.title)
                } label: {
                    SwiftUI.Label("Copy Title", systemImage: "doc.on.doc")
                }

                Button {
                    copyToClipboard(WikipediaURLBuilder.articleURLString(forTitle: article.title))
                } label: {
                    SwiftUI.Label("Copy Wikipedia Link", systemImage: "link")
                }
            }
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            if let article = holiday.article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: referenceDate
                )
            }
        }
    }

    @ViewBuilder
    private var rowContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(holiday.text)
                    .font(.system(size: 12, weight: .medium))
                    .lineSpacing(1.1)
                    .lineLimit(3)
                if let article = holiday.article {
                    Text(article.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func copyToClipboard(_ value: String) {
        _ = SystemBridge.copyText(value)
    }
}

#Preview {
    ContentView()
        .environment(AppState())
}
