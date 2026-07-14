import SwiftUI

struct DiscoverSearchResultsSurface: View {
    let searchCoordinator: SearchCoordinator
    let screenModel: DiscoverScreenModel
    let savedTitles: Set<String>
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let referenceDate: Date
    let onOpen: (WikipediaService.SearchResult, Bool) -> Void

    static func scrollID(for result: WikipediaService.SearchResult) -> String {
        "discover-search-result:\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
    }

    private var statusSubtitle: String {
        let count = searchCoordinator.searchResults.count
        if searchCoordinator.isLoading {
            return count == 0 ? "Searching Wikipedia" : "\(count) found · Updating"
        }
        if searchCoordinator.errorMessage != nil && count == 0 {
            return "Search unavailable"
        }
        return "\(count) \(count == 1 ? "match" : "matches")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "Search Results", subtitle: statusSubtitle)
            if searchCoordinator.isLoading && searchCoordinator.searchResults.isEmpty {
                AppLoadingListPlaceholder(
                    title: "Searching Wikipedia",
                    message: "Matching titles, summaries, and context for \"\(searchCoordinator.searchText)\".",
                    detail: "Discover search",
                    symbol: "magnifyingglass",
                    tone: .accent,
                    rowCount: 5
                )
            } else if let searchError = searchCoordinator.errorMessage,
                      searchCoordinator.searchResults.isEmpty {
                ColumnEmptyStateView(
                    title: Text("Search Unavailable"),
                    systemImage: "wifi.exclamationmark",
                    description: Text(verbatim: searchError),
                    style: .quiet
                ) {
                    Button("Try Again", systemImage: "arrow.clockwise") {
                        searchCoordinator.retrySearch()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .frame(minHeight: 220)
            } else if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
                ColumnEmptyStateView(
                    title: "No Matching Articles",
                    systemImage: "magnifyingglass",
                    description: "Try another title, topic, or spelling.",
                    style: .quiet
                )
                .frame(minHeight: 220)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(searchCoordinator.searchResults.prefix(20).enumerated()), id: \.element.id) { index, result in
                        let rowKey = "search:\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                        let isSaved = savedTitles.contains(ReadStateSync.normalizedTitle(result.title))
                        DiscoverSearchResultRow(
                            result: result,
                            isSaved: isSaved,
                            isKeyboardFocused: searchCoordinator.selectedIndex == index
                        ) {
                            searchCoordinator.selectedIndex = index
                            onOpen(result, SystemBridge.isCommandPressed)
                        }
                        .id(Self.scrollID(for: result))
                        .contextMenu {
                            SearchResultContextMenuContent(
                                result: result,
                                allLists: allLists,
                                allLabels: allLabels,
                                allTags: allTags,
                                onOpen: { inNewTab in
                                    onOpen(result, inNewTab)
                                },
                                onShowPageViews: {
                                    screenModel.presentSearchResultPageViewsPopover(
                                        rowKey: rowKey,
                                        title: result.title
                                    )
                                }
                            )
                        }
                        .popover(
                            isPresented: Binding(
                                get: { screenModel.activeSearchResultPageViewsPopover?.rowKey == rowKey },
                                set: { isPresented in
                                    guard !isPresented else { return }
                                    screenModel.dismissSearchResultPageViewsPopover(for: rowKey)
                                }
                            ),
                            arrowEdge: .trailing
                        ) {
                            if let payload = screenModel.activeSearchResultPageViewsPopover, payload.rowKey == rowKey {
                                DiscoverPageViewsPopoverContent(
                                    title: payload.title,
                                    referenceDate: referenceDate
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
