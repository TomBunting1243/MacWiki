import SwiftData
import SwiftUI

struct DiscoverTimeMachineStageView: View {
    let screenModel: DiscoverScreenModel
    let discoverFeedStore: DiscoverFeedStore
    let responsiveLayout: DiscoverResponsiveLayoutProfile
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let isAppeared: Bool
    let reduceMotion: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: responsiveLayout.timeMachineStageSpacing) {
            DiscoverTimeMachineControlsView(
                screenModel: screenModel,
                discoverFeedStore: discoverFeedStore,
                responsiveLayout: responsiveLayout,
                isScanning: screenModel.isLoadingSelectedDate
            )

            DiscoverFeedSurface(
                discoverFeedStore: discoverFeedStore,
                referenceDate: screenModel.discoverReferenceDate,
                responsiveLayout: responsiveLayout,
                isSearchFieldFocused: isSearchFieldFocused,
                refreshGeneration: refreshGeneration,
                allLists: allLists,
                allLabels: allLabels,
                allTags: allTags,
                isAppeared: isAppeared,
                reduceMotion: reduceMotion,
                isLoadingSelectedDate: screenModel.isLoadingSelectedDate,
                onRetry: screenModel.refreshDiscover,
                onOpen: onOpen
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
