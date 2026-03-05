import SwiftUI
import SwiftData

private enum SidebarSearchLayoutClass {
    case compact
    case regular
    case wide

    init(width: CGFloat) {
        if width < SidebarSearchMetrics.compactWidthThreshold {
            self = .compact
        } else if width < SidebarSearchMetrics.wideWidthThreshold {
            self = .regular
        } else {
            self = .wide
        }
    }
}

private enum SidebarSearchMetrics {
    static let compactWidthThreshold: CGFloat = 252
    static let wideWidthThreshold: CGFloat = 320
    static let titleBottomPadding: CGFloat = 6
    static let fieldHeight: CGFloat = 28
    static let fieldCornerRadius: CGFloat = 10
    static let badgeCornerRadius: CGFloat = 5

    static func rowSpacing(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 2
        case .regular:
            return 3
        case .wide:
            return 4
        }
    }

    static func rowInsetHorizontal(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 6
        case .regular:
            return 8
        case .wide:
            return 10
        }
    }

    static func sectionLabelSize(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 10.5
        case .regular:
            return 11
        case .wide:
            return 11.5
        }
    }

    static func sectionHeaderHorizontalPadding(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 10
        case .regular:
            return 12
        case .wide:
            return 14
        }
    }

    static func fieldHorizontalPadding(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 8
        case .regular:
            return 10
        case .wide:
            return 12
        }
    }

    static func searchFieldFontSize(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 12.5
        case .regular:
            return 13.5
        case .wide:
            return 14
        }
    }

    static func controlsSpacing(for layoutClass: SidebarSearchLayoutClass) -> CGFloat {
        switch layoutClass {
        case .compact:
            return 10
        case .regular:
            return 12
        case .wide:
            return 14
        }
    }
}

private enum SidebarSearchReadFilter {
    case all
    case unread
}

private enum SidebarSearchSortMode: String, CaseIterable {
    case relevance = "Relevance"
    case title = "Title"
    case articleLength = "Length"
}

struct SidebarSearchView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \ArticleState.updatedAt, order: .reverse) private var articleStates: [ArticleState]

    @State private var searchCoordinator = SearchCoordinator(
        debounceMilliseconds: SearchCoordinator.defaultDebounceMilliseconds,
        minimumQueryLength: 2,
        supportsTrending: true,
        searchPrefetchLimit: 24,
        trendingPrefetchLimit: 24
    )
    @State private var activePageViewsPopover: SidebarSearchPageViewsPopoverPayload?
    @State private var readFilter: SidebarSearchReadFilter = .all
    @State private var sortMode: SidebarSearchSortMode = .relevance
    @State private var selectedVisibleIndex = 0
    @State private var selectedVisibleResultID: String?
    @State private var wordCountByTitle: [String: Int] = [:]
    @State private var wordCountAttemptedTitleKeys: Set<String> = []

    @FocusState private var isSearchFieldFocused: Bool

    private var usesCompactHeaderChrome: Bool {
        appState.sidebarVisible
    }

    private var titleBarHeight: CGFloat {
        if usesCompactHeaderChrome {
            return ColumnChromeMetrics.topBarHeight
        }
        return max(
            appState.windowTopObscuredHeight,
            ColumnChromeMetrics.titleBarClearance + 14
        )
    }

    private var titleBarBottomPadding: CGFloat {
        usesCompactHeaderChrome ? 0 : SidebarSearchMetrics.titleBottomPadding
    }

    private var articleStateByURL: [String: ArticleState] {
        articleStates.reduce(into: [:]) { result, state in
            result[state.articleURLString] = state
        }
    }

    private var articleStateByTitle: [String: ArticleState] {
        articleStates.reduce(into: [:]) { result, state in
            result[ReadStateSync.normalizedTitle(state.articleTitle)] = state
        }
    }

    private var savedArticleByTitle: [String: SavedArticle] {
        var lookup: [String: SavedArticle] = [:]
        for list in allLists {
            for article in list.articles {
                let key = ReadStateSync.normalizedTitle(article.title)
                if lookup[key] == nil {
                    lookup[key] = article
                }
            }
        }
        return lookup
    }

    private var currentArticleTitleNormalized: String? {
        guard let activeId = appState.activeTabId,
              let tab = appState.openTabs.first(where: { $0.id == activeId }) else {
            return nil
        }
        return ReadStateSync.normalizedTitle(tab.article.title)
    }

    private var sourceResults: [WikipediaService.SearchResult] {
        searchCoordinator.hasQuery ? searchCoordinator.searchResults : searchCoordinator.trendingArticles
    }

    private var visibleResults: [WikipediaService.SearchResult] {
        processedResults(from: sourceResults)
    }

    private var visibleResultIDs: [String] {
        visibleResults.map(\.id)
    }

    private var visibleResultCount: Int {
        visibleResults.count
    }

    private var visibleReadCount: Int {
        visibleResults.reduce(into: 0) { count, result in
            if effectiveReadState(for: article(from: result)) {
                count += 1
            }
        }
    }

    private var visibleUnreadCount: Int {
        visibleResults.count - visibleReadCount
    }

    private var sourceResultCount: Int {
        sourceResults.count
    }

    private var wordCountPrefetchFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(sortMode)
        hasher.combine(searchCoordinator.hasQuery)
        hasher.combine(sourceResults.count)
        for result in sourceResults {
            hasher.combine(ReadStateSync.normalizedTitle(result.title))
        }
        return hasher.finalize()
    }

    private var resultsSectionTitle: String {
        searchCoordinator.hasQuery ? "Results" : "Trending Today"
    }

    private func articleState(for title: String) -> ArticleState? {
        let urlString = ReadStateSync.urlString(for: title)
        if let state = articleStateByURL[urlString] {
            return state
        }
        return articleStateByTitle[ReadStateSync.normalizedTitle(title)]
    }

    private func effectiveReadState(for article: Article) -> Bool {
        if let state = articleState(for: article.title) {
            return state.isRead
        }
        if let saved = savedArticleByTitle[ReadStateSync.normalizedTitle(article.title)] {
            return saved.isRead
        }
        return false
    }

    private func readingProgress(for article: Article) -> Double {
        if isCurrentArticle(article.title),
           let liveProgress = appState.liveReadingProgress(forTitle: article.title) {
            return liveProgress
        }
        return articleState(for: article.title)?.readingProgress ?? 0
    }

    private func isCurrentArticle(_ title: String) -> Bool {
        currentArticleTitleNormalized == ReadStateSync.normalizedTitle(title)
    }

    private func processedResults(
        from results: [WikipediaService.SearchResult]
    ) -> [WikipediaService.SearchResult] {
        var scoped = results

        if readFilter == .unread {
            scoped = scoped.filter { result in
                !effectiveReadState(for: article(from: result))
            }
        }

        switch sortMode {
        case .relevance:
            return scoped
        case .title:
            return scoped.sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        case .articleLength:
            return scoped.sorted { lhs, rhs in
                let lhsCount = resolvedWordCount(for: lhs) ?? -1
                let rhsCount = resolvedWordCount(for: rhs) ?? -1
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }

    private func resolvedWordCount(for result: WikipediaService.SearchResult) -> Int? {
        let key = ReadStateSync.normalizedTitle(result.title)
        if let cached = wordCountByTitle[key] {
            return cached
        }
        if let savedWordCount = savedArticleByTitle[key]?.wordCount {
            return savedWordCount
        }
        return nil
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

    private func clampSelectedVisibleIndex() {
        guard !visibleResults.isEmpty else {
            selectedVisibleIndex = 0
            selectedVisibleResultID = nil
            return
        }
        selectedVisibleIndex = min(max(selectedVisibleIndex, 0), visibleResults.count - 1)
        selectedVisibleResultID = visibleResults[selectedVisibleIndex].id
    }

    private func reconcileSelection(with resultIDs: [String]) {
        guard !resultIDs.isEmpty else {
            selectedVisibleIndex = 0
            selectedVisibleResultID = nil
            return
        }

        if let selectedVisibleResultID,
           let matchingIndex = resultIDs.firstIndex(of: selectedVisibleResultID) {
            selectedVisibleIndex = matchingIndex
            return
        }

        selectedVisibleIndex = min(max(selectedVisibleIndex, 0), resultIDs.count - 1)
        selectedVisibleResultID = resultIDs[selectedVisibleIndex]
    }

    private func moveSelectionDown() {
        guard !visibleResults.isEmpty else {
            selectedVisibleIndex = 0
            selectedVisibleResultID = nil
            return
        }
        selectedVisibleIndex = min(selectedVisibleIndex + 1, visibleResults.count - 1)
        selectedVisibleResultID = visibleResults[selectedVisibleIndex].id
    }

    private func moveSelectionUp() {
        guard !visibleResults.isEmpty else {
            selectedVisibleIndex = 0
            selectedVisibleResultID = nil
            return
        }
        selectedVisibleIndex = max(selectedVisibleIndex - 1, 0)
        selectedVisibleResultID = visibleResults[selectedVisibleIndex].id
    }

    private func unresolvedWordCountTitles(limit: Int = 32) -> [String] {
        guard sortMode == .articleLength else { return [] }

        var keysSeen = Set<String>()
        var unresolved: [String] = []
        unresolved.reserveCapacity(limit)

        for result in sourceResults {
            let key = ReadStateSync.normalizedTitle(result.title)
            guard keysSeen.insert(key).inserted else { continue }
            guard resolvedWordCount(for: result) == nil else { continue }
            guard !wordCountAttemptedTitleKeys.contains(key) else { continue }

            unresolved.append(result.title)
            if unresolved.count >= limit {
                break
            }
        }

        return unresolved
    }

    @MainActor
    private func prefetchWordCountsIfNeeded() async {
        guard sortMode == .articleLength else { return }

        let titlesToFetch = unresolvedWordCountTitles()
        guard !titlesToFetch.isEmpty else { return }

        let wikipediaService = WikipediaService.shared

        for title in titlesToFetch {
            guard !Task.isCancelled else { return }

            let key = ReadStateSync.normalizedTitle(title)
            if wordCountAttemptedTitleKeys.contains(key) {
                continue
            }
            wordCountAttemptedTitleKeys.insert(key)

            if let metadata = try? await wikipediaService.fetchPageMetadata(title) {
                guard !Task.isCancelled else { return }
                wordCountByTitle[key] = metadata.wordCount
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let layoutClass = SidebarSearchLayoutClass(width: proxy.size.width)

            VStack(spacing: 0) {
                headerBar(layoutClass: layoutClass)
                resultsContent(layoutClass: layoutClass)
            }
            .background {
                SidebarPaneBackground()
                    .ignoresSafeArea(.container, edges: [.top, .bottom])
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if let launchQuery = appState.consumeLaunchSidebarSearchQuery() {
                searchCoordinator.searchText = launchQuery
            }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
            searchCoordinator.loadTrendingIfNeeded()
        }
        .onChange(of: searchCoordinator.searchText) { _, _ in
            selectedVisibleIndex = 0
            selectedVisibleResultID = nil
        }
        .onChange(of: visibleResultIDs) { _, _ in
            reconcileSelection(with: visibleResultIDs)
        }
        .task(id: wordCountPrefetchFingerprint) {
            await prefetchWordCountsIfNeeded()
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                moveSelectionDown()
            case .up:
                moveSelectionUp()
            default:
                break
            }
        }
        .onExitCommand {
            dismissSearch()
        }
        .onDisappear {
            searchCoordinator.cancel()
        }
    }

    private func headerBar(layoutClass: SidebarSearchLayoutClass) -> some View {
        let isCompactLayout = layoutClass == .compact

        return VStack(spacing: 0) {
            headerTitleBar

            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                .frame(height: 0.5)

            ZStack {
                WindowDragHandle(minLength: 80)
                    .frame(maxWidth: .infinity)

                HStack(spacing: SidebarSearchMetrics.controlsSpacing(for: layoutClass)) {
                    searchField(layoutClass: layoutClass)

                    if !isCompactLayout {
                        Text("esc")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: SidebarSearchMetrics.badgeCornerRadius, style: .continuous)
                                    .fill(.quaternary)
                            )
                    }

                    Button {
                        dismissSearch()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: ChromeIconMetrics.compactButtonSize, height: ChromeIconMetrics.compactButtonSize)
                            .background(
                                RoundedRectangle(cornerRadius: TopChromeControlMetrics.accessoryCornerRadius(compact: true), style: .continuous)
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Close Search")
                }
                .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
            }
            .frame(height: ColumnChromeMetrics.topBarHeight)

            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                .frame(height: 0.5)

            resultsControlsBar(layoutClass: layoutClass)
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

    private var headerTitleBar: some View {
        ZStack(alignment: usesCompactHeaderChrome ? .leading : .bottomLeading) {
            WindowDragHandle(minLength: 140)
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Text("Search")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Text(headerMetadataText)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
            .padding(.bottom, titleBarBottomPadding)
        }
        .frame(height: titleBarHeight)
    }

    private func resultsControlsBar(layoutClass: SidebarSearchLayoutClass) -> some View {
        let showScopeCounts = layoutClass != .compact

        return ZStack {
            WindowDragHandle(minLength: 80)
                .frame(maxWidth: .infinity)

            HStack(spacing: SidebarSearchMetrics.controlsSpacing(for: layoutClass)) {
                Button {
                    readFilter = (readFilter == .unread) ? .all : .unread
                } label: {
                    Image(systemName: readFilter == .unread ? "circle.inset.filled" : "circle")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(readFilter == .unread ? Color.accentColor : .secondary)
                        .frame(width: ChromeIconMetrics.buttonSize, height: ChromeIconMetrics.buttonSize)
                }
                .buttonStyle(.plain)
                .help(readFilter == .unread ? "Show all results" : "Show unread only")

                Spacer(minLength: 0)

                Text("\(visibleResultCount)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                + Text(" ")
                + Text(visibleResultCount == 1 ? "result" : "results")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)

                if showScopeCounts && readFilter == .unread && sourceResultCount != visibleResultCount {
                    Text("·")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text("of \(sourceResultCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Menu {
                    ForEach(SidebarSearchSortMode.allCases, id: \.self) { mode in
                        Button {
                            sortMode = mode
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
                    Button {
                        batchMarkVisibleResults(asRead: true)
                    } label: {
                        SwiftUI.Label("Mark Visible as Read", systemImage: "checkmark.circle")
                    }
                    .disabled(visibleUnreadCount == 0)

                    Button {
                        batchMarkVisibleResults(asRead: false)
                    } label: {
                        SwiftUI.Label("Mark Visible as Unread", systemImage: "circle")
                    }
                    .disabled(visibleReadCount == 0)

                    if !allLists.isEmpty {
                        Divider()
                        Menu("Save Visible to List") {
                            ForEach(allLists) { list in
                                Button(list.name) {
                                    saveVisibleResults(to: list)
                                }
                            }
                        }
                        .disabled(visibleResults.isEmpty)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                        .frame(width: ChromeIconMetrics.buttonSize, height: ChromeIconMetrics.buttonSize)
                }
                .menuStyle(.borderlessButton)
                .help("Actions")
            }
            .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
        }
        .frame(height: ColumnChromeMetrics.topBarHeight - 2)
    }

    private func searchField(layoutClass: SidebarSearchLayoutClass) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Wikipedia...", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: SidebarSearchMetrics.searchFieldFontSize(for: layoutClass)))
                .focused($isSearchFieldFocused)
                .onSubmit {
                    selectCurrentResultFromKeyboard()
                }

            if searchCoordinator.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else if searchCoordinator.hasInput {
                Button {
                    searchCoordinator.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SidebarSearchMetrics.fieldHorizontalPadding(for: layoutClass))
        .frame(height: SidebarSearchMetrics.fieldHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SidebarSearchMetrics.fieldCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.055))
        )
        .overlay {
            RoundedRectangle(cornerRadius: SidebarSearchMetrics.fieldCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10), lineWidth: 0.6)
        }
    }

    private var headerMetadataText: String {
        if searchCoordinator.hasQuery {
            if searchCoordinator.isLoading {
                return "Searching"
            }
            let filteredCount = visibleResultCount
            let totalCount = searchCoordinator.searchResults.count
            if readFilter == .unread && filteredCount != totalCount {
                return "\(filteredCount) of \(totalCount)"
            }
            return filteredCount == 1 ? "1 result" : "\(filteredCount) results"
        }
        if searchCoordinator.isTrendingLoading {
            return "Trending"
        }
        if !searchCoordinator.trendingArticles.isEmpty {
            return "Trending Today"
        }
        return "Wikipedia"
    }

    @ViewBuilder
    private func resultsContent(layoutClass: SidebarSearchLayoutClass) -> some View {
        if let error = searchCoordinator.errorMessage {
            SidebarSearchStateBanner(
                title: "Search Unavailable",
                message: error,
                symbol: "exclamationmark.triangle.fill",
                footnote: "Try again in a moment",
                tone: .error,
                layoutClass: layoutClass
            )
        } else if searchCoordinator.hasQuery {
            if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
                SidebarSearchStateBanner(
                    title: "No Results",
                    message: "No articles found for \"\(searchCoordinator.searchText)\"",
                    symbol: "sparkle.magnifyingglass",
                    footnote: "Try fewer words or broader terms",
                    tone: .neutral,
                    layoutClass: layoutClass
                )
            } else if visibleResults.isEmpty && !searchCoordinator.isLoading {
                SidebarSearchStateBanner(
                    title: "No Unread Matches",
                    message: "Everything in these results is marked read.",
                    symbol: "checkmark.circle",
                    footnote: "Toggle unread filter to see all matches",
                    tone: .neutral,
                    layoutClass: layoutClass
                )
            } else {
                resultList(
                    results: visibleResults,
                    sectionTitle: resultsSectionTitle,
                    layoutClass: layoutClass
                )
            }
        } else if searchCoordinator.isTrendingLoading {
            VStack(spacing: 10) {
                ProgressView()
                    .padding(.top, 8)
                Text("Loading Trending…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchCoordinator.trendingArticles.isEmpty {
            SidebarSearchStateBanner(
                title: "Search Wikipedia",
                message: "Ask for a person, place, event, or idea.",
                symbol: "sparkles",
                footnote: "Type to search • ↑↓ navigate • ↩ open",
                tone: .search,
                layoutClass: layoutClass
            )
        } else if visibleResults.isEmpty {
            SidebarSearchStateBanner(
                title: "No Unread Results",
                message: "Everything in trending is marked read.",
                symbol: "checkmark.circle",
                footnote: "Toggle unread filter to see all results",
                tone: .neutral,
                layoutClass: layoutClass
            )
        } else {
            resultList(
                results: visibleResults,
                sectionTitle: resultsSectionTitle,
                layoutClass: layoutClass
            )
        }
    }

    private func resultList(
        results: [WikipediaService.SearchResult],
        sectionTitle: String,
        layoutClass: SidebarSearchLayoutClass
    ) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SidebarSearchMetrics.rowSpacing(for: layoutClass)) {
                    HStack(spacing: 6) {
                        Text(sectionTitle)
                            .font(.system(size: SidebarSearchMetrics.sectionLabelSize(for: layoutClass), weight: .semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Spacer(minLength: 0)
                        Text("\(results.count)")
                            .font(.system(size: SidebarSearchMetrics.sectionLabelSize(for: layoutClass), weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, SidebarSearchMetrics.sectionHeaderHorizontalPadding(for: layoutClass))
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        let rowKey = "sidebar-search:\(sectionTitle):\(index):\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                        let article = article(from: result)
                        let isRead = effectiveReadState(for: article)
                        let progress = readingProgress(for: article)

                        ArticleListItem(
                            isRead: isRead,
                            progress: progress,
                            isCurrent: isCurrentArticle(article.title),
                            isSelected: index == selectedVisibleIndex,
                            onTap: {
                                selectedVisibleIndex = index
                                selectedVisibleResultID = result.id
                                let inNewTab = appState.searchContext == .newTab || SystemBridge.isCommandPressed
                                selectResult(result, inNewTab: inNewTab)
                            }
                        ) { isHovered, _ in
                            ArticleRowWithFetch(
                                article: article,
                                isHovered: isHovered
                            )
                        }
                        .id(index)
                        .padding(.horizontal, SidebarSearchMetrics.rowInsetHorizontal(for: layoutClass))
                        .contextMenu {
                            SearchResultContextMenuContent(
                                result: result,
                                allLists: allLists,
                                onOpen: { inNewTab in
                                    selectedVisibleIndex = index
                                    selectedVisibleResultID = result.id
                                    selectResult(result, inNewTab: inNewTab)
                                },
                                onSaveToList: { list in
                                    SearchResultActions.saveToList(
                                        result,
                                        list: list,
                                        modelContext: modelContext
                                    )
                                },
                                onShowPageViews: {
                                    activePageViewsPopover = SidebarSearchPageViewsPopoverPayload(
                                        rowKey: rowKey,
                                        title: result.title
                                    )
                                }
                            )
                        }
                        .popover(isPresented: pageViewsPopoverBinding(for: rowKey), arrowEdge: .trailing) {
                            if let payload = activePageViewsPopover, payload.rowKey == rowKey {
                                SidebarPageViewsPopoverContent(
                                    title: payload.title,
                                    referenceDate: Date()
                                )
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: selectedVisibleIndex) { _, newIndex in
                guard results.indices.contains(newIndex) else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newIndex, anchor: .center)
                }
            }
        }
    }

    private func article(from result: WikipediaService.SearchResult) -> Article {
        Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
    }

    private func selectCurrentResultFromKeyboard() {
        guard visibleResults.indices.contains(selectedVisibleIndex) else { return }
        let selected = visibleResults[selectedVisibleIndex]
        var inNewTab = appState.searchContext == .newTab
        if SystemBridge.isCommandPressed {
            inNewTab.toggle()
        }
        selectResult(selected, inNewTab: inNewTab)
    }

    private func selectResult(_ result: WikipediaService.SearchResult, inNewTab: Bool = false) {
        let article = article(from: result)
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: article)
        } else {
            appState.openArticle(article, inNewTab: inNewTab)
        }
    }

    private func batchMarkVisibleResults(asRead: Bool) {
        guard !visibleResults.isEmpty else { return }
        for result in visibleResults {
            let article = article(from: result)
            _ = ReadStateSync.applyReadState(
                asRead,
                for: article,
                in: modelContext,
                appState: appState
            )
        }
    }

    private func saveVisibleResults(to list: ReadingList) {
        guard !visibleResults.isEmpty else { return }
        for result in visibleResults {
            SearchResultActions.saveToList(
                result,
                list: list,
                modelContext: modelContext
            )
        }
    }

    private func dismissSearch() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            appState.showSearch = false
        }
    }
}

private struct SidebarSearchPageViewsPopoverPayload {
    let rowKey: String
    let title: String
}

private enum SidebarSearchBannerTone {
    case search
    case neutral
    case error

    var symbolColor: Color {
        switch self {
        case .search:
            return Color.secondary
        case .neutral:
            return Color.secondary
        case .error:
            return Color(nsColor: .systemOrange)
        }
    }
}

private struct SidebarSearchStateBanner: View {
    let title: String
    let message: String
    let symbol: String
    let footnote: String?
    let tone: SidebarSearchBannerTone
    let layoutClass: SidebarSearchLayoutClass

    var body: some View {
        VStack(spacing: verticalSpacing) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tone.symbolColor)

            Text(title)
                .font(.system(size: titleFontSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(detailText)
                .font(.system(size: detailFontSize, weight: .medium))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var symbolSize: CGFloat {
        switch layoutClass {
        case .compact:
            return 24
        case .regular:
            return 28
        case .wide:
            return 30
        }
    }

    private var titleFontSize: CGFloat {
        switch layoutClass {
        case .compact:
            return 14.5
        case .regular:
            return 15.5
        case .wide:
            return 16
        }
    }

    private var detailFontSize: CGFloat {
        switch layoutClass {
        case .compact:
            return 11.5
        case .regular:
            return 12
        case .wide:
            return 12.5
        }
    }

    private var topPadding: CGFloat {
        switch layoutClass {
        case .compact:
            return 16
        case .regular:
            return 22
        case .wide:
            return 26
        }
    }

    private var horizontalPadding: CGFloat {
        switch layoutClass {
        case .compact:
            return 14
        case .regular:
            return 18
        case .wide:
            return 20
        }
    }

    private var verticalSpacing: CGFloat {
        switch layoutClass {
        case .compact:
            return 8
        case .regular:
            return 9
        case .wide:
            return 10
        }
    }

    private var detailText: String {
        guard let footnote, !footnote.isEmpty else {
            return message
        }
        return "\(message) \(footnote)"
    }
}
