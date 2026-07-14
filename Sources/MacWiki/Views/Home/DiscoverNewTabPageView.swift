import SwiftData
import SwiftUI

/// Apple News-inspired discovery hub used by the New Tab page.
struct DiscoverNewTabPageView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
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
    @State private var articleLookupModel = DiscoverArticleLookupModel()
    @State private var isAppeared = false
    @State private var responsiveLayout = DiscoverResponsiveLayoutProfile.initial

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
        articleLookupModel.index
    }

    private var savedArticleTitlesNormalized: Set<String> {
        articleLookup.savedArticleTitlesNormalized
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
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: responsiveLayout.pageSectionSpacing) {
                    DiscoverSearchBarView(
                        searchCoordinator: searchCoordinator,
                        discoverFeedStore: discoverFeedStore,
                        onOpenSelectedResult: openSelectedSearchResult,
                        onMoveSelection: moveSearchSelection,
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
                            responsiveLayout: responsiveLayout,
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
                .frame(maxWidth: responsiveLayout.pageMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, responsiveLayout.horizontalPadding)
                .padding(.top, 24)
                .padding(.bottom, 48)
                .onGeometryChange(for: DiscoverResponsiveLayoutProfile?.self) { proxy in
                    DiscoverResponsiveLayoutProfile(width: proxy.size.width)
                } action: { newLayout in
                    guard let newLayout, newLayout != responsiveLayout else { return }
                    responsiveLayout = newLayout
                }
            }
            .onChange(of: searchCoordinator.selectedIndex) { _, _ in
                guard searchCoordinator.hasQuery,
                      let selectedResult = searchCoordinator.selectedResult(usingTrendingFallback: false) else {
                    return
                }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    scrollProxy.scrollTo(
                        DiscoverSearchResultsSurface.scrollID(for: selectedResult)
                    )
                }
            }
        }
        .background(DiscoverEditionBackground().ignoresSafeArea())
        .onAppear {
            screenModel.selectedDiscoverDate = appState.selectedDiscoverDate
            articleLookupModel.start(modelContext: modelContext)
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
            articleLookupModel.stop()
            if !reduceMotion {
                isAppeared = false
            }
            searchCoordinator.cancel()
            screenModel.handleDisappear()
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
        .onChange(of: screenModel.selectedDiscoverDate) { _, newDate in
            screenModel.handleSelectedDateChange(isSearchActive: searchCoordinator.hasQuery)
            Task { @MainActor in
                await Task.yield()
                guard screenModel.selectedDiscoverDate == newDate else { return }
                if appState.selectedDiscoverDate != newDate {
                    appState.selectedDiscoverDate = newDate
                }
            }
        }
        .onChange(of: appState.selectedDiscoverDate) { _, newDate in
            Task { @MainActor in
                await Task.yield()
                guard appState.selectedDiscoverDate == newDate else { return }
                if screenModel.selectedDiscoverDate != newDate {
                    screenModel.selectedDiscoverDate = newDate
                }
            }
        }
        .task {
            screenModel.queueInitialLoad()
        }
    }

    private func updateTimeTravelSkeletonVisibility() {
        screenModel.updateTimeTravelSkeletonVisibility(reduceMotion: reduceMotion)
    }

    private func moveSearchSelection(_ direction: MoveCommandDirection) {
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

    private func openSelectedSearchResult() {
        guard let selectedResult = searchCoordinator.selectedResult(usingTrendingFallback: false) else {
            return
        }
        open(selectedResult, inNewTab: SystemBridge.isCommandPressed)
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

}
