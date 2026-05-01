import SwiftData
import SwiftUI

struct DiscoverTimeMachineStageView: View {
    let screenModel: DiscoverScreenModel
    let discoverFeedStore: DiscoverFeedStore
    let discoverContentWidth: CGFloat
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let isAppeared: Bool
    let reduceMotion: Bool
    let showsTimeTravelSkeleton: Bool
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void

    private var stageSpacing: CGFloat {
        discoverContentWidth < 820 ? 18 : 22
    }

    var body: some View {
        VStack(alignment: .leading, spacing: stageSpacing) {
            DiscoverTimeMachineControlsView(
                screenModel: screenModel,
                discoverFeedStore: discoverFeedStore,
                discoverContentWidth: discoverContentWidth,
                isScanning: showsTimeTravelSkeleton
            )

            DiscoverFeedSurface(
                discoverFeedStore: discoverFeedStore,
                referenceDate: screenModel.discoverReferenceDate,
                availableWidth: discoverContentWidth,
                isSearchFieldFocused: isSearchFieldFocused,
                refreshGeneration: refreshGeneration,
                allLists: allLists,
                allLabels: allLabels,
                allTags: allTags,
                isAppeared: isAppeared,
                reduceMotion: reduceMotion,
                showsTimeTravelSkeleton: showsTimeTravelSkeleton,
                onOpen: onOpen
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
