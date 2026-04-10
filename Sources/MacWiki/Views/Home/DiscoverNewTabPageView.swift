import SwiftData
import SwiftUI

/// Apple News-inspired discovery hub used by the New Tab page.
struct DiscoverNewTabPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    @State private var searchCoordinator = SearchCoordinator(
        debounceMilliseconds: SearchCoordinator.defaultDebounceMilliseconds,
        minimumQueryLength: 2,
        supportsTrending: false,
        searchPrefetchLimit: 24
    )
    @State private var screenModel = DiscoverScreenModel()
    @State private var articleLookupSnapshot = ArticleLookupIndex.empty
    @State private var isAppeared = false
    @State private var discoverContentWidth: CGFloat = 1040

    @FocusState private var isSearchFocused: Bool

    private var discoverReferenceDate: Date {
        screenModel.discoverReferenceDate
    }

    private var discoverFeedStore: DiscoverFeedStore {
        screenModel.discoverFeedStore
    }

    private var shouldQueueTimeTravelSkeleton: Bool {
        screenModel.shouldQueueTimeTravelSkeleton
    }

    private var showsTimeTravelSkeleton: Bool {
        screenModel.showsTimeTravelSkeleton
    }

    private var articleLookup: ArticleLookupIndex {
        articleLookupSnapshot
    }

    private var articleLookupFingerprint: Int {
        articleLookupIndexFingerprint(readingLists: allLists)
    }

    private var savedArticleTitlesNormalized: Set<String> {
        articleLookup.savedArticleTitlesNormalized
    }

    private func refreshArticleLookupSnapshot() {
        articleLookupSnapshot = ArticleLookupIndex(readingLists: allLists)
    }

    @AppStorage(DiscoverStartMode.storageKey) private var discoverStartMode: DiscoverStartMode = .discoverFeed
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var isWikiHopEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var isWikiHopPostV1Enabled = false

    private var isWikiHopAvailable: Bool {
        isWikiHopPostV1Enabled && isWikiHopEnabled
    }

    var body: some View {
        if isWikiHopAvailable && discoverStartMode == .wikiHop {
            WikiHopLobbyView()
        } else {
            discoverFeedContent
        }
    }

    private var discoverFeedContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: discoverContentWidth < 820 ? 18 : 22) {
                DiscoverSearchBarView(
                    searchCoordinator: searchCoordinator,
                    discoverFeedStore: discoverFeedStore,
                    onOpenFirstResult: {
                        if let first = searchCoordinator.searchResults.first {
                            open(first, inNewTab: false)
                        }
                    },
                    onRefreshDiscover: {
                        screenModel.refreshDiscover()
                    },
                    onClearSearch: {
                        searchCoordinator.clearSearch()
                    },
                    isSearchFocused: $isSearchFocused
                )

                if searchCoordinator.hasQuery {
                    DiscoverSearchResultsSurface(
                        searchCoordinator: searchCoordinator,
                        screenModel: screenModel,
                        savedTitles: savedArticleTitlesNormalized,
                        allLists: allLists,
                        allLabels: allLabels,
                        allTags: allTags,
                        referenceDate: discoverReferenceDate,
                        onOpen: open
                    )
                } else {
                    DiscoverTimeMachineControlsView(
                        screenModel: screenModel,
                        discoverFeedStore: discoverFeedStore,
                        discoverContentWidth: discoverContentWidth
                    )
                    DiscoverFeedSurface(
                        discoverFeedStore: discoverFeedStore,
                        referenceDate: discoverReferenceDate,
                        availableWidth: discoverContentWidth,
                        isSearchFieldFocused: isSearchFocused,
                        refreshGeneration: screenModel.discoverRefreshGeneration,
                        allLists: allLists,
                        allLabels: allLabels,
                        allTags: allTags,
                        isAppeared: isAppeared,
                        reduceMotion: reduceMotion,
                        showsTimeTravelSkeleton: showsTimeTravelSkeleton,
                        onOpen: open
                    )
                }
            }
            .frame(maxWidth: 1040, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 48)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            updateDiscoverContentWidth(proxy.size.width)
                        }
                        .onChange(of: proxy.size.width) { _, newWidth in
                            updateDiscoverContentWidth(newWidth)
                        }
                }
            }
        }
        .background(discoverBackground.ignoresSafeArea())
        .onAppear {
            refreshArticleLookupSnapshot()
            if reduceMotion {
                isAppeared = true
            } else {
                withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.88)) {
                    isAppeared = true
                }
            }
            isSearchFocused = true
            updateTimeTravelSkeletonVisibility()
        }
        .onDisappear {
            if !reduceMotion {
                isAppeared = false
            }
            searchCoordinator.cancel()
            screenModel.handleDisappear()
        }
        .onChange(of: articleLookupFingerprint) { _, _ in
            refreshArticleLookupSnapshot()
        }
        .onChange(of: shouldQueueTimeTravelSkeleton) { _, _ in
            updateTimeTravelSkeletonVisibility()
        }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced {
                isAppeared = true
            }
            updateTimeTravelSkeletonVisibility()
        }
        .onChange(of: screenModel.selectedDiscoverDate) { _, _ in
            screenModel.handleSelectedDateChange(isSearchActive: searchCoordinator.hasQuery)
        }
        .task {
            screenModel.queueInitialLoad()
        }
    }

    private func updateTimeTravelSkeletonVisibility() {
        screenModel.updateTimeTravelSkeletonVisibility(reduceMotion: reduceMotion)
    }

    private var discoverBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.accentColor.opacity(0.12), Color.accentColor.opacity(0)],
                        center: .center,
                        startRadius: 20,
                        endRadius: 260
                    )
                )
                .offset(x: 250, y: -260)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.blue.opacity(0.08), Color.blue.opacity(0)],
                        center: .center,
                        startRadius: 10,
                        endRadius: 220
                    )
                )
                .offset(x: -320, y: 180)

            RoundedRectangle(cornerRadius: 320, style: .continuous)
                .stroke(Color.primary.opacity(0.03), lineWidth: 1)
                .scaleEffect(1.2)
                .offset(y: 180)
        }
    }

    private func open(_ result: WikipediaService.SearchResult, inNewTab: Bool) {
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
    }

    private func updateDiscoverContentWidth(_ newWidth: CGFloat) {
        guard newWidth > 0 else { return }
        guard abs(discoverContentWidth - newWidth) > 0.5 else { return }
        discoverContentWidth = newWidth
    }

}
