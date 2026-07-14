import Foundation
import SwiftUI

struct DiscoverFeedSections: View {
    let feed: WikipediaService.DiscoverFeed
    let responsiveLayout: DiscoverResponsiveLayoutProfile
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void
    @Environment(\.openURL) var openURL
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) var reduceMotion
    @State var editionModel = DiscoverEditionModel()
    @State var activePageViewsPopover: DiscoverPageViewsPopoverPayload?
    @State var isCollectionsKeyboardFocusActive = false
    @State var focusedCollectionLane: DiscoverCollectionLane = .mostRead
    @State var focusedMostReadRowIndex = 0
    @State var focusedLongestRowIndex = 0
    @State var isTodayMostReadExpanded = true
    @State var isMostReadCollectionExpanded = false
    @State var isLongestReadsCollectionExpanded = false

    var body: some View {
        LazyVStack(alignment: .leading, spacing: sectionSpacing) {
            leadEditionStage
            collectionsStage
            mediaSpotlightSection
            temporalExplorationStage
        }
        .background {
            collectionsKeyboardShortcutHost
        }
        .onAppear {
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: feed.dateKey) { _, _ in
            activePageViewsPopover = nil
        }
        .onChange(of: collectionsFocusDataKey) { _, _ in
            normalizeCollectionsKeyboardFocus()
        }
        .onChange(of: isSearchFieldFocused) { _, focused in
            if focused {
                applyCollectionsKeyboardState(
                    DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
                )
            }
        }
        .onMoveCommand { direction in
            moveCollectionsFocus(direction)
        }
        .onExitCommand {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
        }
        .task(id: todayMostReadLoadKey) {
            editionModel.updateTodayMostRead(
                isExpanded: isTodayMostReadExpanded,
                forceRefresh: refreshGeneration > 0
            )
        }
        .task(id: allTimeMostReadLoadKey) {
            editionModel.updateAllTimeMostRead(
                showsMostRead: isMostReadCollectionExpanded,
                showsLongestReads: isLongestReadsCollectionExpanded,
                limit: allTimeMostReadLoadLimit
            )
        }
        .task(id: todayTrendPulseLoadKey) {
            editionModel.updateTodayTrendPulse(
                isExpanded: isTodayMostReadExpanded,
                results: todayMostReadItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: trendPulseLoadKey) {
            editionModel.updateMostReadTrendPulse(
                isExpanded: isMostReadCollectionExpanded,
                results: trendPulseItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: wordCountLoadKey) {
            editionModel.updateWordCounts(
                isExpanded: isLongestReadsCollectionExpanded,
                results: longestReadCandidates,
                retryFailed: refreshGeneration > 0
            )
        }
        .task(id: featuredArticleLoadKey) {
            editionModel.updateFeaturedArticle(title: featuredArticleTitle)
        }
        .onDisappear {
            editionModel.cancelAll()
        }
    }
}
