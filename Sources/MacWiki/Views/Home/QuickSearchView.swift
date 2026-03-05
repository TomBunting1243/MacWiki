import SwiftUI
import SwiftData

// Quick search overlay with live Wikipedia search
struct QuickSearchView: View {
    static let idealSize = CGSize(width: 1040, height: 720)

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @State private var searchCoordinator = SearchCoordinator(
        debounceMilliseconds: SearchCoordinator.defaultDebounceMilliseconds,
        minimumQueryLength: 2,
        supportsTrending: true,
        searchPrefetchLimit: 24,
        trendingPrefetchLimit: 24
    )

    // UI State
    @State private var isAppeared = false
    @State private var hoveredIndex: Int? = nil
    @State private var activePageViewsPopover: QuickSearchPageViewsPopoverPayload?
    @FocusState private var isSearchFieldFocused: Bool

    private let modalSize: CGSize

    init(modalSize: CGSize = Self.idealSize) {
        self.modalSize = modalSize
    }

    private var savedArticleTitlesNormalized: Set<String> {
        SearchResultActions.savedArticleTitlesNormalized(from: allLists)
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

    var body: some View {
        VStack(spacing: 0) {
            // Search field with liquid glass style
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search Wikipedia...", text: $searchCoordinator.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        if searchCoordinator.hasQuery,
                           let selected = searchCoordinator.selectedResult(usingTrendingFallback: false) {
                            var inNewTab = appState.searchContext == .newTab
                            if SystemBridge.isCommandPressed {
                                inNewTab.toggle()
                            }
                            selectResult(selected, inNewTab: inNewTab)
                        }
                    }

                if searchCoordinator.isLoading {
                    AppLoadingActivityMark(tone: .accent)
                        .frame(width: 20, height: 20)
                } else if searchCoordinator.hasInput {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            searchCoordinator.clearSearch()
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }

                // Keyboard shortcut hint
                Text("esc")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.quaternary)
                    )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            Divider()
                .opacity(0.35)

            // Results area
            resultsContent
        }
        .frame(width: modalSize.width, height: modalSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.07), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.10), radius: 18, y: 6)
        }
        .scaleEffect(isAppeared ? 1 : 0.985)
        .opacity(isAppeared ? 1 : 0)
        .onAppear {
            withAnimation(AppLoadingMotion.overlaySettle) {
                isAppeared = true
            }
            DispatchQueue.main.async {
                isSearchFieldFocused = true
            }
            searchCoordinator.loadTrendingIfNeeded()
        }
        .onMoveCommand { direction in
            guard searchCoordinator.hasQuery else { return }
            switch direction {
            case .down:
                searchCoordinator.moveSelectionDown(usingTrendingFallback: false)
            case .up:
                searchCoordinator.moveSelectionUp(usingTrendingFallback: false)
            default:
                break
            }
        }
        .onExitCommand {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                appState.showSearch = false
            }
        }
        .onDisappear {
            searchCoordinator.cancel()
        }
    }

    @ViewBuilder
    private var resultsContent: some View {
        if let error = searchCoordinator.errorMessage {
            ContentUnavailableView(
                "Search Error",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
            .frame(maxHeight: .infinity)
        } else if !searchCoordinator.hasQuery {
            if searchCoordinator.isTrendingLoading {
                AppLoadingListPlaceholder(
                    title: "Top Reads",
                    message: "Fetching today's most-read articles from Wikipedia.",
                    detail: "Quick Search",
                    symbol: "chart.line.uptrend.xyaxis",
                    tone: .accent,
                    rowCount: 6
                )
                .padding(14)
                .frame(maxHeight: .infinity, alignment: .top)
            } else if !searchCoordinator.trendingArticles.isEmpty {
                let savedTitles = savedArticleTitlesNormalized
                let columnCount = modalSize.width >= 820 ? 2 : 1
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .foregroundStyle(.secondary)
                        Text("Top Reads Today")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()

                        // Context hint
                        let openAction = appState.searchContext == .newTab ? "New Tab" : "Open"
                        Text("\(openAction) with return")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount),
                            spacing: 10
                        ) {
                            ForEach(Array(searchCoordinator.trendingArticles.enumerated()), id: \.element.id) { index, result in
                                let rowKey = "quick-trending:\(index):\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                                let isSaved = savedTitles.contains(ReadStateSync.normalizedTitle(result.title))
                                Button {
                                    let inNewTab = appState.searchContext == .newTab || SystemBridge.isCommandPressed
                                    selectResult(result, inNewTab: inNewTab)
                                } label: {
                                    TrendingCard(
                                        result: result,
                                        isHovered: index == hoveredIndex,
                                        isSaved: isSaved,
                                        isLarge: false
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(result.title)
                                .id("trending-\(index)")
                                .onHover { hovering in
                                    hoveredIndex = hovering ? index : nil
                                }
                                .contextMenu {
                                    SearchResultContextMenuContent(
                                        result: result,
                                        allLists: allLists,
                                        onOpen: { inNewTab in
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
                                            activePageViewsPopover = QuickSearchPageViewsPopoverPayload(
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
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(.tertiary)
                    Text("Search Wikipedia")
                        .font(.title3)
                        .fontWeight(.medium)

                    // Context-aware prompt
                    let openAction = appState.searchContext == .newTab ? "New Tab" : "Open"
                    let altAction = appState.searchContext == .newTab ? "Open" : "New Tab"
                    Text("Type to search • ↑↓ to navigate • ⏎ to \(openAction) • ⌘⏎ \(altAction)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxHeight: .infinity)
            }
        } else if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
            ContentUnavailableView(
                "No Results",
                systemImage: "doc.text.magnifyingglass",
                description: Text("No articles found for \"\(searchCoordinator.searchText)\"")
            )
            .frame(maxHeight: .infinity)
        } else if searchCoordinator.isLoading && searchCoordinator.searchResults.isEmpty {
            AppLoadingListPlaceholder(
                title: "Searching Wikipedia",
                message: "Matching titles and summaries for \"\(searchCoordinator.searchText)\".",
                detail: "Live results",
                symbol: "magnifyingglass",
                tone: .accent,
                rowCount: 5
            )
            .padding(14)
            .frame(maxHeight: .infinity, alignment: .top)
        } else {
            let savedTitles = savedArticleTitlesNormalized
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(searchCoordinator.searchResults.enumerated()), id: \.element.id) { index, result in
                            let rowKey = "quick-results:\(index):\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                            let isSaved = savedTitles.contains(ReadStateSync.normalizedTitle(result.title))
                            Button {
                                let inNewTab = appState.searchContext == .newTab || SystemBridge.isCommandPressed
                                selectResult(result, inNewTab: inNewTab)
                            } label: {
                                SearchResultRow(
                                    result: result,
                                    isSaved: isSaved,
                                    isSelected: index == searchCoordinator.selectedIndex,
                                    isHovered: index == hoveredIndex
                                )
                                    .id(index)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 3)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(index == searchCoordinator.selectedIndex ? Color.accentColor.opacity(0.10) : (index == hoveredIndex ? Color.primary.opacity(0.035) : .clear))
                                    }
                                    .contentShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(result.title)
                            .onHover { hovering in
                                hoveredIndex = hovering ? index : nil
                            }
                            .contextMenu {
                                SearchResultContextMenuContent(
                                    result: result,
                                    allLists: allLists,
                                    onOpen: { inNewTab in
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
                                        activePageViewsPopover = QuickSearchPageViewsPopoverPayload(
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
                .onChange(of: searchCoordinator.selectedIndex) { _, newIndex in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func selectResult(_ result: WikipediaService.SearchResult, inNewTab: Bool = false) {
        let article = Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: article)
        } else {
            appState.openArticle(article, inNewTab: inNewTab)
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            appState.showSearch = false
        }
    }
}

private struct QuickSearchPageViewsPopoverPayload {
    let rowKey: String
    let title: String
}

// Row displaying a search result
struct SearchResultRow: View {
    let result: WikipediaService.SearchResult
    var isSaved: Bool = false
    var isSelected: Bool = false
    var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            Group {
                if let url = result.thumbnailURL {
                    AsyncImage(
                        url: url,
                        transaction: Transaction(animation: .easeOut(duration: 0.18))
                    ) { phase in
                        switch phase {
                        case .empty:
                            AppLoadingThumbnailPlaceholder(
                                width: 62,
                                height: 62,
                                cornerRadius: 8,
                                tone: .neutral,
                                symbol: "doc.text"
                            )
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(4)
                                .transition(.opacity)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "doc.text")
                                        .foregroundStyle(.tertiary)
                                }
                        @unknown default:
                            Rectangle().fill(.quaternary)
                        }
                    }
                } else {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .frame(width: 62, height: 62)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Title and description
            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)

                if let description = result.description {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            // Selection indicator
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.quaternary)
                    )
            }
        }
        .padding(.vertical, 4)
    }
}

// Card view for a trending article
struct TrendingCard: View {
    let result: WikipediaService.SearchResult
    var isHovered: Bool = false
    var isSaved: Bool = false
    var isLarge: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Expanded Thumbnail
            ZStack(alignment: .topTrailing) {
                let imageHeight: CGFloat = isLarge ? 118 : 96

                Group {
                    if let url = result.thumbnailURL {
                        AsyncImage(
                            url: url,
                            transaction: Transaction(animation: .easeOut(duration: 0.18))
                        ) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    AppLoadingSkeletonBar(
                                        width: nil,
                                        height: imageHeight,
                                        cornerRadius: 0,
                                        tone: .accent
                                    )
                                    Image(systemName: "photo")
                                        .foregroundStyle(.tertiary)
                                }
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .padding(8)
                                    .transition(.opacity)
                            case .failure:
                                Rectangle()
                                    .fill(.quaternary)
                                    .overlay {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.tertiary)
                                    }
                            @unknown default:
                                Rectangle().fill(.quaternary)
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundStyle(.tertiary)
                            }
                    }
                }
                .frame(height: imageHeight)
                .frame(maxWidth: .infinity)
                .background(.quaternary.opacity(0.20))

                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.7)
                                }
                        )
                        .padding(8)
                }
            }

            // Text Content
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let description = result.description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
        }
        .frame(height: isLarge ? 182 : 168)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.primary.opacity(0.018))
                .shadow(color: .black.opacity(isHovered ? 0.08 : 0.04), radius: 6, y: 3)
        }
        .scaleEffect(isHovered ? 1.01 : 1)
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.92), value: isHovered)
    }
}
