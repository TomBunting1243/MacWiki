import SwiftUI
import SwiftData

struct DirectoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStorageKey.Recents.scope) private var recentsScope: RecentsScope = .currentTab
    @AppStorage(AppStorageKey.Discover.sidebarTimeMachineHidden) private var discoverSidebarTimeMachineHidden = false
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var wikiHopPostV1Enabled = false
    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection
    var selectedLabel: Label?
    var selectedTag: Tag?
    let sidebarSearchModel: SidebarSearchSurfaceModel
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
    @State private var metadataHydrator = ArticleMetadataHydrator()
    @State private var supplementalReadFilter: DirectoryReadFilter = .all
    @State private var supplementalSortMode: DirectorySupplementalSortMode = .recent
    @State private var selectedSavedArticleIDs: Set<UUID> = []
    @State private var selectionAnchorSavedArticleID: UUID?
    @State private var showDeleteSelectedConfirmation = false
    @State private var articleIndexesSnapshot = DirectoryArticleIndexes.empty
    @State private var visibleSnapshot = DirectoryVisibleSnapshot.empty
    @State private var saveScheduler = DebouncedActionScheduler()
    @State private var pendingPageViewsRowKey: String?
    @State private var activePageViewsPopover: SidebarPageViewsPopoverPayload?
    @State private var discoverDateLoadTask: Task<Void, Never>?
    @State private var sidebarTimeTravelSkeletonDelayTask: Task<Void, Never>?
    @State private var shouldShowDelayedSidebarTimeTravelSkeleton = false
    @State private var isTimeMachineDatePickerPresented = false
    @State private var timeMachineLensLastDragX: CGFloat?
    @State private var timeMachineLensDragAccumulatedX: CGFloat = 0
    @State private var topObscuredHeight: CGFloat = 38

    private let wikipediaService = WikipediaService.shared

    private var selectedDiscoverDate: Date {
        get { appState.selectedDiscoverDate }
        nonmutating set { appState.selectedDiscoverDate = newValue }
    }

    private var selectedDiscoverDateBinding: Binding<Date> {
        Binding(
            get: { appState.selectedDiscoverDate },
            set: { appState.selectedDiscoverDate = $0 }
        )
    }

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }

    private var articleIndexes: DirectoryArticleIndexes {
        articleIndexesSnapshot
    }

    private var directoryVisibleSnapshot: DirectoryVisibleSnapshot {
        visibleSnapshot
    }

    private var articleIndexesFingerprint: Int {
        directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private var visibleSnapshotCandidateTitles: [String] {
        if rootSelection == .discover || (rootSelection == .wikiHop && isWikiHopAvailable) {
            return []
        }

        if let list = selectedList {
            return list.articles.map(\.title)
        }

        if let label = selectedLabel {
            return savedArticles
                .filter { $0.labelId == label.id }
                .map(\.title)
        }

        if let tag = selectedTag {
            return DirectorySnapshotBuilder.taggedArticleTitles(
                for: tag,
                articleStates: articleStates,
                highlights: highlights
            )
        }

        if recentsScope == .currentTab,
           let activeId = appState.activeTabId,
           let tab = appState.openTabs.first(where: { $0.id == activeId }) {
            return DirectorySnapshotBuilder.deduplicatedHistory(tab.history).map(\.article.title)
        }

        return appState.recentArticles.map(\.title)
    }

    private var shouldTrackHydratedWordCountsInVisibleSnapshot: Bool {
        if let list = selectedList {
            return list.sortMode == .articleLength
        }
        return supplementalSortMode == .articleLength
    }

    private var visibleSnapshotFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(articleIndexesFingerprint)
        hasher.combine(rootSelection.rawValue)
        hasher.combine(recentsScope.rawValue)
        hasher.combine(selectedList?.id)
        hasher.combine(selectedLabel?.id)
        hasher.combine(selectedTag?.id)
        hasher.combine(localLabelFilter?.id)
        hasher.combine(localTagFilter?.id)
        hasher.combine(supplementalReadFilter == .unread)
        hasher.combine(supplementalSortMode.rawValue)

        if let list = selectedList {
            hasher.combine(list.filterMode.rawValue)
            hasher.combine(list.sortMode.rawValue)
            hasher.combine(list.articles.count)
            for article in list.articles {
                hasher.combine(article.id)
                hasher.combine(article.manualOrder)
            }
        } else if let label = selectedLabel {
            hasher.combine(label.id)
            let labeledIDs = savedArticles
                .filter { $0.labelId == label.id }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            hasher.combine(labeledIDs.count)
            for id in labeledIDs {
                hasher.combine(id)
            }
        } else if let tag = selectedTag {
            let tagTitles = DirectorySnapshotBuilder.taggedArticleTitles(
                for: tag,
                articleStates: articleStates,
                highlights: highlights
            )
            hasher.combine(tag.id)
            hasher.combine(tagTitles.count)
            for title in tagTitles {
                hasher.combine(ReadStateSync.normalizedTitle(title))
            }
        } else if recentsScope == .currentTab,
                  let activeId = appState.activeTabId,
                  let tab = appState.openTabs.first(where: { $0.id == activeId }) {
            hasher.combine(activeId)
            hasher.combine(tab.currentIndex)
            hasher.combine(tab.history.count)
            for item in tab.history {
                hasher.combine(item.id)
                hasher.combine(item.article.title)
                hasher.combine(item.article.isRead)
            }
        } else {
            hasher.combine(appState.recentArticles.count)
            for article in appState.recentArticles {
                hasher.combine(article.id)
                hasher.combine(article.title)
                hasher.combine(article.isRead)
            }
        }

        if shouldTrackHydratedWordCountsInVisibleSnapshot {
            for title in visibleSnapshotCandidateTitles {
                hasher.combine(ReadStateSync.normalizedTitle(title))
                hasher.combine(metadataHydrator.snapshot(for: title)?.wordCount)
            }
        }

        return hasher.finalize()
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

    private var discoverPulseItems: [WikipediaService.SearchResult] {
        guard let feed = discoverFeedStore.feed else { return [] }
        var items: [WikipediaService.SearchResult] = []
        if let featuredArticle = feed.featuredArticle {
            items.append(featuredArticle)
        }
        items.append(contentsOf: discoverMostReadItems(from: feed))
        return items
    }

    private func titleFingerprint<S: Sequence>(
        _ titles: S,
        seeds: [AnyHashable] = []
    ) -> Int where S.Element == String {
        var hasher = Hasher()
        for seed in seeds {
            hasher.combine(seed)
        }
        for title in titles {
            hasher.combine(ReadStateSync.normalizedTitle(title))
        }
        return hasher.finalize()
    }

    private var discoverTrendingPulseLoadKey: Int {
        guard rootSelection == .discover, let feed = discoverFeedStore.feed else {
            return titleFingerprint([], seeds: [AnyHashable("inactive-discover-pulse")])
        }
        return titleFingerprint(
            discoverPulseItems.map(\.title),
            seeds: [AnyHashable(feed.dateKey), AnyHashable("discover-pulse")]
        )
    }

    private var metadataHydrationRequests: [ArticleMetadataHydrationRequest] {
        guard !isSidebarSearchPresented else { return [] }

        if rootSelection == .discover {
            return discoverTrendingItems.map { result in
                metadataHydrationRequest(for: discoverArticle(from: result))
            }
        }

        if selectedList != nil {
            return orderedVisibleSavedArticles.map { metadataHydrationRequest(for: $0) }
        }

        if let label = selectedLabel {
            return LabelArticlesSnapshot(
                label: label,
                savedArticles: savedArticles,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                tagFilter: localTagFilter,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedWordCount(for:)
            ).articles.map { metadataHydrationRequest(for: $0) }
        }

        if let tag = selectedTag {
            return TagArticlesSnapshot(
                tag: tag,
                articleStates: articleStates,
                highlights: highlights,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                tagFilter: localTagFilter,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedWordCount(for:)
            ).articles.map { metadataHydrationRequest(for: $0) }
        }

        if recentsScope == .currentTab,
           let activeId = appState.activeTabId,
           appState.openTabs.contains(where: { $0.id == activeId }) {
            return directoryVisibleSnapshot.tabHistoryItems.map { metadataHydrationRequest(for: $0.article) }
        }

        return directoryVisibleSnapshot.recentArticles.map { metadataHydrationRequest(for: $0) }
    }

    private var metadataHydrationFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(rootSelection.rawValue)
        hasher.combine(selectedList?.id)
        hasher.combine(selectedLabel?.id)
        hasher.combine(selectedTag?.id)
        hasher.combine(recentsScope.rawValue)
        hasher.combine(metadataHydrationRequests.count)

        for request in metadataHydrationRequests {
            hasher.combine(ReadStateSync.normalizedTitle(request.title))
            hasher.combine(request.articleID)
            hasher.combine(request.savedArticle?.id)
            hasher.combine(request.description == nil)
            hasher.combine(request.extract == nil)
            hasher.combine(request.thumbnailURL == nil)
            hasher.combine(request.wordCount == nil)
        }

        return hasher.finalize()
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
        rootSelection == .discover ||
        rootSelection == .recents
    }

    private var isSidebarSearchPresented: Bool {
        appState.showSearch
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
        if rootSelection == .discover {
            return "Discover"
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

    private func refreshVisibleSnapshot() {
        visibleSnapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: selectedList,
            selectedLabel: selectedLabel,
            selectedTag: selectedTag,
            rootSelection: rootSelection,
            recentsScope: recentsScope,
            activeTabId: appState.activeTabId,
            openTabs: appState.openTabs,
            recentArticles: appState.recentArticles,
            savedArticles: savedArticles,
            articleStates: articleStates,
            highlights: highlights,
            localLabelFilter: localLabelFilter,
            localTagFilter: localTagFilter,
            supplementalReadFilter: supplementalReadFilter,
            supplementalSortMode: supplementalSortMode,
            articleIndexes: articleIndexes,
            resolvedSavedArticleWordCount: resolvedWordCount(for:),
            resolvedArticleWordCount: resolvedWordCount(for:)
        )
    }

    private func requestModelContextSave() {
        saveScheduler.schedule { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    private func flushScheduledModelContextSave() {
        saveScheduler.flush { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
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
                SidebarSearchView(model: sidebarSearchModel)
            } else {
                directoryList
            }
        }
        .onAppear {
            updateSidebarTimeTravelSkeletonVisibility()
        }
        .onChange(of: shouldQueueSidebarTimeTravelSkeleton) { _, _ in
            updateSidebarTimeTravelSkeletonVisibility()
        }
        .task(id: isSidebarSearchPresented ? nil : articleIndexesFingerprint) {
            guard !isSidebarSearchPresented else { return }
            await Task.yield()
            refreshArticleIndexesSnapshot()
        }
        .task(id: isSidebarSearchPresented ? nil : visibleSnapshotFingerprint) {
            guard !isSidebarSearchPresented else { return }
            await Task.yield()
            refreshVisibleSnapshot()
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
            flushScheduledModelContextSave()
            metadataHydrator.cancel()
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

    private var pinnedDirectoryHeaderHeight: CGFloat { 68 }

    private var plainDirectoryTopInset: CGFloat {
        max(0, topObscuredHeight) + 10
    }

    private var directoryList: some View {
        ZStack(alignment: .top) {
            directoryScrollSurface
            .contentMargins(
                .top,
                shouldShowTopDirectoryChrome ? pinnedDirectoryHeaderHeight : plainDirectoryTopInset,
                for: .scrollIndicators
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                if shouldShowTopDirectoryChrome {
                    directoryPinnedHeader
                }
            }

            if shouldShowRecentsEmptyStateOverlay {
                recentsEmptyStateOverlay
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsSidebarTimeTravelSkeleton)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateTopObscuredHeight(proxy.safeAreaInsets.top)
                    }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newValue in
                        updateTopObscuredHeight(newValue)
                    }
            }
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
                results: discoverPulseItems,
                referenceDate: discoverTrendReferenceDate
            )
        }
        .task(id: pinnedArticleFingerprint) {
            await wikipediaService.replacePinnedArticleTitles(Array(pinnedArticleTitles))
        }
        .task(id: metadataHydrationFingerprint) {
            metadataHydrator.queueLoad(
                requests: metadataHydrationRequests,
                appState: appState,
                modelContext: modelContext
            )
        }
    }

    @ViewBuilder
    private var directoryScrollSurface: some View {
        if rootSelection == .discover {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    discoverSections()
                }
            }
            .scrollIndicators(.visible)
        } else {
            List {
                directoryContent
            }
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
                    ? pinnedDirectoryHeaderHeight
                    : plainDirectoryTopInset
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
                metadataHydrator: metadataHydrator,
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
                metadataHydrator: metadataHydrator,
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
            if orderedVisibleSavedArticles.isEmpty {
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
                ForEach(orderedVisibleSavedArticles) { savedArticle in
                    let isRead = effectiveReadState(for: savedArticle.title, fallback: savedArticle.isRead)
                    let progress = readingProgress(for: savedArticle.title)
                    let tags = tagsForSavedArticle(savedArticle)
                    SavedArticleRow(
                        savedArticle: savedArticle,
                        hydratedMetadata: hydratedMetadata(for: savedArticle.title),
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

    // MARK: - Directory Controls

    private var directoryPinnedHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            directoryHeaderIdentity

            Spacer(minLength: 12)

            directoryHeaderControls
        }
        .padding(.horizontal, 12)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
    }

    private var directoryTopContentSpacerRow: some View {
        Color.clear
            .frame(height: plainDirectoryTopInset)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets())
    }

    private func updateTopObscuredHeight(_ newValue: CGFloat) {
        let resolved = max(0, newValue)
        guard abs(topObscuredHeight - resolved) > 0.5 else { return }
        DispatchQueue.main.async {
            guard abs(topObscuredHeight - resolved) > 0.5 else { return }
            topObscuredHeight = resolved
        }
    }

    private var directoryHeaderIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(topDirectoryTitle)
                .font(MacWikiTypography.columnHeaderTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            directoryHeaderMetadataLine
        }
    }

    @ViewBuilder
    private var directoryHeaderMetadataLine: some View {
        if rootSelection == .discover {
            discoverHeaderMetadataLine
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    directoryCountLabel

                    if hasSelectedSavedArticles {
                        Text("·")
                            .font(MacWikiTypography.columnHeaderMetadata)
                            .foregroundStyle(.tertiary)

                        directorySelectionLabel
                    }
                }

                directoryCountLabel
            }
        }
    }

    private var discoverHeaderMetadataLine: some View {
        HStack(spacing: 6) {
            Text(discoverTimeMachineHeaderDateLabel)
                .font(MacWikiTypography.columnHeaderMetadata)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if discoverFeedStore.isLoading {
                Text("·")
                    .font(MacWikiTypography.columnHeaderMetadata)
                    .foregroundStyle(.tertiary)

                Text(discoverFeedStore.feed == nil ? "Loading" : "Updating")
                    .font(MacWikiTypography.columnHeaderMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var directoryCountLabel: some View {
        HStack(spacing: 3) {
            Text("\(directoryVisibleArticleCount)")
                .font(MacWikiTypography.columnHeaderMetadata)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(directoryVisibleArticleCount == 1 ? "article" : "articles")
                .font(MacWikiTypography.columnHeaderMetadata)
                .foregroundStyle(.secondary)
        }
    }

    private var directorySelectionLabel: some View {
        Text("\(selectedSavedArticleCount) selected")
            .font(MacWikiTypography.columnHeaderMetadata)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var directoryHeaderControls: some View {
        if rootSelection == .discover {
            discoverHeaderControls
        } else {
            ControlGroup {
                directoryUnreadFilterButton
                directorySortMenu
                directoryBatchActionsMenu
            }
            .controlSize(.small)
        }
    }

    private var discoverHeaderControls: some View {
        ControlGroup {
            Button {
                queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)
            } label: {
                SwiftUI.Label("Refresh Discover", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
                    .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
            }
            .disabled(discoverFeedStore.isLoading)
            .help("Refresh Discover")
        }
        .controlSize(.small)
    }

    private var directoryUnreadFilterButton: some View {
        let unreadFilterEnabled = isUnreadFilterEnabled

        return Button {
            toggleUnreadFilter()
        } label: {
            Image(systemName: unreadFilterEnabled ? "circle.inset.filled" : "circle")
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(unreadFilterEnabled ? Color.accentColor : .secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help(unreadFilterEnabled ? "Show all articles" : "Show unread only")
        .accessibilityLabel("Unread only")
        .accessibilityValue(unreadFilterEnabled ? "Enabled" : "Disabled")
    }

    private var directorySortMenu: some View {
        let sortMode = activeDirectorySortMode

        return Menu {
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
            SwiftUI.Label("Sort Articles", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help("Sort")
    }

    private var directoryBatchActionsMenu: some View {
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
            SwiftUI.Label("Batch Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help("Batch actions")
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
            requestModelContextSave()
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
            requestModelContextSave()
        } else {
            supplementalSortMode = mode
        }
    }

    private var directoryVisibleTitles: [String] {
        directoryVisibleSnapshot.visibleTitles
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
        directoryVisibleSnapshot.listArticles
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
        directoryVisibleSnapshot.visibleUnreadCount
    }

    private var visibleReadCount: Int {
        directoryVisibleSnapshot.visibleReadCount
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
        ArticleLibraryActions.batchMarkTitles(
            directoryVisibleTitles,
            asRead: asRead,
            modelContext: modelContext,
            appState: appState,
            touchedList: selectedList
        )
    }

    private func metadataHydrationRequest(for savedArticle: SavedArticle) -> ArticleMetadataHydrationRequest {
        ArticleMetadataHydrationRequest(
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            extract: savedArticle.extract,
            thumbnailURL: savedArticle.thumbnailURL,
            wordCount: savedArticle.wordCount,
            savedArticle: savedArticle
        )
    }

    private func metadataHydrationRequest(for article: Article) -> ArticleMetadataHydrationRequest {
        let saved = savedArticle(for: article.title)
        return ArticleMetadataHydrationRequest(
            title: article.title,
            articleID: article.id,
            description: saved?.articleDescription ?? article.description,
            extract: saved?.extract ?? article.extract,
            thumbnailURL: saved?.thumbnailURL ?? article.thumbnailURL,
            wordCount: saved?.wordCount ?? article.wordCount,
            savedArticle: saved
        )
    }

    private func hydratedMetadata(for title: String) -> ArticleMetadataHydrationSnapshot? {
        metadataHydrator.snapshot(for: title)
    }

    private func resolvedWordCount(for savedArticle: SavedArticle) -> Int {
        metadataHydrator.resolvedWordCount(for: savedArticle)
    }

    private func resolvedWordCount(for article: Article) -> Int {
        metadataHydrator.resolvedWordCount(for: article)
    }

    private func toggleReadStatus(_ article: SavedArticle) {
        ArticleLibraryActions.toggleReadStatus(
            for: article,
            effectiveReadState: effectiveReadState(for: article.title, fallback: article.isRead),
            modelContext: modelContext,
            appState: appState
        )
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
            .accessibilityLabel("Clear tag filter")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private func applyLabelToSelectedSavedArticles(_ labelId: UUID?) {
        ArticleLibraryActions.applyLabel(
            labelId,
            to: selectedSavedArticles,
            modelContext: modelContext
        )
    }

    private func addTagToSelectedSavedArticles(_ tag: Tag) {
        ArticleLibraryActions.addTag(
            tag,
            to: selectedSavedArticles,
            modelContext: modelContext
        )
    }

    private func removeTagFromSelectedSavedArticles(_ tag: Tag) {
        ArticleLibraryActions.removeTag(
            tag,
            from: selectedSavedArticles,
            modelContext: modelContext
        )
    }

    private func addSelectedSavedArticles(to targetList: ReadingList) {
        ArticleLibraryActions.addSavedArticles(
            selectedSavedArticles,
            to: targetList,
            modelContext: modelContext
        )
    }

    private func deleteSelectedSavedArticles() {
        ArticleLibraryActions.deleteSavedArticles(
            selectedSavedArticles,
            modelContext: modelContext
        )
        clearSavedArticleSelection()
    }

    private func removeFromList(_ article: SavedArticle, list: ReadingList) {
        ArticleLibraryActions.removeFromList(
            article,
            list: list,
            modelContext: modelContext
        )
    }

    private func moveArticle(_ article: SavedArticle, from source: ReadingList?, to target: ReadingList) {
        ArticleLibraryActions.moveArticle(
            article,
            from: source,
            to: target,
            modelContext: modelContext
        )
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
        delayNanoseconds: UInt64 = 170_000_000
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
                    selection: selectedDiscoverDateBinding,
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

    private var timeMachineScanningBadge: some View {
        HStack(spacing: 5) {
            AppLoadingActivityMark(tone: .retro)

            Text("SCANNING")
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(timeMachineAccentPrimary.opacity(0.86))
                .lineLimit(1)
        }
        .fixedSize()
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(timeMachineAccentPrimary.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 0.7)
                )
                .padding(.vertical, 3)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
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

                        Spacer(minLength: 0)

                        if showsSidebarTimeTravelSkeleton {
                            timeMachineScanningBadge
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
                        }
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
                .overlay {
                    if showsSidebarTimeTravelSkeleton {
                        SidebarGlitchScanlineOverlay(lineOpacity: colorScheme == .dark ? 0.030 : 0.020)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .blendMode(.screen)
                            .opacity(reduceMotion ? 0.08 : 0.16)
                            .allowsHitTesting(false)
                    }
                }
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.16 : 0.07), radius: 4, y: 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: showsSidebarTimeTravelSkeleton)
                .help("Time Machine lets you see what people were reading in the past.")
                .padding(.vertical, 3)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            }
        }

        if showsSidebarTimeTravelSkeleton {
            sidebarTimeTravelLoadingSections
        } else if discoverFeedStore.isLoading && discoverFeedStore.feed == nil {
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
                        .font(MacWikiTypography.compactRowTitle)
                    Text(discoverError)
                        .font(MacWikiTypography.settingsHelp)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        } else if let feed = discoverFeedStore.feed {
            let mostReadItems = discoverMostReadItems(from: feed)

            if let featured = feed.featuredArticle {
                Section("Featured Article") {
                    discoverArticleRow(featured, showTrendPulse: true)
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

    @ViewBuilder
    private var sidebarTimeTravelLoadingSections: some View {
        Section("Featured Article") {
            SidebarTimeTravelLoadingRow(index: 0, style: .feature)
        }

        Section("Most Read") {
            ForEach(1..<6, id: \.self) { index in
                SidebarTimeTravelLoadingRow(index: index, style: .article)
            }
        }

        Section("This Day in History") {
            ForEach(6..<9, id: \.self) { index in
                SidebarTimeTravelLoadingRow(index: index, style: .timeline)
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
            accessibilityTitle: article.title,
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
                hydratedMetadata: hydratedMetadata(for: article.title),
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
        .discoverContentRowSpacing()
    }

    private func discoverArticle(from result: WikipediaService.SearchResult) -> Article {
        Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
    }

    private func articleDragPayload(for article: Article, isRead: Bool) -> SavedArticleDragPayload {
        let metadata = hydratedMetadata(for: article.title)
        return SavedArticleDragPayload(
            title: article.title,
            articleDescription: metadata?.description ?? article.description,
            extract: metadata?.extract ?? article.extract,
            thumbnailURL: metadata?.thumbnailURL ?? article.thumbnailURL,
            isRead: isRead,
            wordCount: metadata?.wordCount ?? article.wordCount
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
            if !shouldShowTopDirectoryChrome {
                directoryTopContentSpacerRow
            }

            if tab.history.isEmpty {
                Text("No history")
                    .foregroundStyle(.secondary)
            } else {
                let filteredHistory = directoryVisibleSnapshot.tabHistoryItems
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

                    // History rows open directly; save/move prompts stay scoped to Library rows.
                    ArticleListItem(
                        accessibilityTitle: item.article.title,
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
                            hydratedMetadata: hydratedMetadata(for: item.article.title),
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
                    .draggable(articleDragPayload(for: item.article, isRead: isRead)) {
                        SwiftUI.Label(item.article.title, systemImage: "doc.text")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    @ViewBuilder
    func recentArticlesSection() -> some View {
        Section {
            if !shouldShowTopDirectoryChrome {
                directoryTopContentSpacerRow
            }

            let filteredRecents = directoryVisibleSnapshot.recentArticles
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
                        hydratedMetadata: hydratedMetadata(for: article.title),
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
                        alwaysShowsLabelMetadata: true,
                        showsListMembership: true,
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
                        accessibilityTitle: article.title,
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
                            hydratedMetadata: hydratedMetadata(for: article.title),
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
                    .draggable(articleDragPayload(for: article, isRead: isRead)) {
                        SwiftUI.Label(article.title, systemImage: "doc.text")
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState(persistenceMode: .ephemeral))
}
