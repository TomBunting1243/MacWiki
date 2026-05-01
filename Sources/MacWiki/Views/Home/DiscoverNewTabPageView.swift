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

    private var discoverPageMaxWidth: CGFloat {
        if discoverContentWidth >= 1540 { return 1320 }
        if discoverContentWidth >= 1240 { return 1160 }
        return 980
    }

    private var discoverHorizontalPadding: CGFloat {
        if discoverContentWidth < 720 { return 18 }
        if discoverContentWidth >= 1540 { return 42 }
        return 28
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
            LazyVStack(alignment: .leading, spacing: discoverContentWidth < 820 ? 16 : 20) {
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
                    DiscoverTimeMachineStageView(
                        screenModel: screenModel,
                        discoverFeedStore: discoverFeedStore,
                        discoverContentWidth: discoverContentWidth,
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
            .frame(maxWidth: discoverPageMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, discoverHorizontalPadding)
            .padding(.top, 24)
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
        .background(DiscoverEditionBackground().ignoresSafeArea())
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
