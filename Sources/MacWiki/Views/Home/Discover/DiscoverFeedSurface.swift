import SwiftUI

struct DiscoverFeedSurface: View {
    let discoverFeedStore: DiscoverFeedStore
    let referenceDate: Date
    let availableWidth: CGFloat
    let isSearchFieldFocused: Bool
    let refreshGeneration: Int
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let isAppeared: Bool
    let reduceMotion: Bool
    let showsTimeTravelSkeleton: Bool
    let onRetry: () -> Void
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void

    var body: some View {
        if discoverFeedStore.isLoading && discoverFeedStore.feed == nil {
            DiscoverIntroLoadingView(referenceDate: referenceDate)
                .frame(maxWidth: .infinity, minHeight: 260)
        } else if let discoverError = discoverFeedStore.errorMessage, discoverFeedStore.feed == nil {
            VStack(alignment: .leading, spacing: 8) {
                Text("Discover feed unavailable")
                    .font(.headline)
                Text(discoverError)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 4)
            }
            .padding(18)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if let feed = discoverFeedStore.feed {
            ZStack(alignment: .topLeading) {
                DiscoverFeedSections(
                    feed: feed,
                    availableWidth: availableWidth,
                    isSearchFieldFocused: isSearchFieldFocused,
                    refreshGeneration: refreshGeneration,
                    allLists: allLists,
                    allLabels: allLabels,
                    allTags: allTags,
                    showsTimeTravelSkeleton: showsTimeTravelSkeleton,
                    timeMachineTargetDate: referenceDate,
                    onOpen: onOpen
                )
                .opacity(isAppeared ? 1 : 0)
                .offset(y: reduceMotion ? 0 : (isAppeared ? 0 : 10))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: isAppeared)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showsTimeTravelSkeleton)
        }
    }
}
