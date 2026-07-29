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
        .onKeyPress(.return, phases: .down) { keyPress in
            guard isCollectionsKeyboardFocusActive,
                  canOpenFocusedCollectionItem,
                  !isSearchFieldFocused,
                  activePageViewsPopover == nil else {
                return .ignored
            }
            openFocusedCollectionItem(
                inNewTab: keyPress.modifiers.contains(.command)
            )
            return .handled
        }
        .onExitCommand {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
        }
        .task(id: todayMostReadLoadPlan) {
            editionModel.updateTodayMostRead(todayMostReadLoadPlan)
        }
        .task(id: allTimeMostReadLoadPlan) {
            editionModel.updateAllTimeMostRead(allTimeMostReadLoadPlan)
        }
        .task(id: todayTrendPulseLoadPlan) {
            editionModel.updateTodayTrendPulse(
                todayTrendPulseLoadPlan,
                results: todayMostReadItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: trendPulseLoadPlan) {
            editionModel.updateMostReadTrendPulse(
                trendPulseLoadPlan,
                results: trendPulseItems,
                referenceDate: mostReadPulseReferenceDate
            )
        }
        .task(id: wordCountLoadPlan) {
            editionModel.updateWordCounts(
                wordCountLoadPlan,
                results: longestReadCandidates
            )
        }
        .task(id: featuredArticleLoadPlan) {
            editionModel.updateFeaturedArticle(featuredArticleLoadPlan)
        }
        .onDisappear {
            editionModel.cancelAll()
        }
    }
}
