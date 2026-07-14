import SwiftUI

struct DiscoverFeedSurface: View {
    let discoverFeedStore: DiscoverFeedStore
    let referenceDate: Date
    let responsiveLayout: DiscoverResponsiveLayoutProfile
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
            ColumnEmptyStateView(
                title: Text("Discover Unavailable"),
                systemImage: "wifi.exclamationmark",
                description: Text(verbatim: discoverError)
            ) {
                Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                    .keyboardShortcut(.defaultAction)
            }
            .frame(minHeight: 260)
        } else if let feed = discoverFeedStore.feed {
            VStack(alignment: .leading, spacing: 12) {
                if let discoverError = discoverFeedStore.errorMessage {
                    GroupBox {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(verbatim: discoverError)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            Spacer(minLength: 12)

                            Button("Try Again", systemImage: "arrow.clockwise", action: onRetry)
                                .controlSize(.small)
                        }
                    } label: {
                        SwiftUI.Label(
                            "Showing the Last Available Edition",
                            systemImage: "exclamationmark.triangle"
                        )
                    }
                    .accessibilityElement(children: .contain)
                }

                DiscoverFeedSections(
                    feed: feed,
                    responsiveLayout: responsiveLayout,
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
