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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiscoverSectionHeader(title: "Search Results", subtitle: "\(searchCoordinator.searchResults.count) matches")
            if searchCoordinator.isLoading && searchCoordinator.searchResults.isEmpty {
                AppLoadingListPlaceholder(
                    title: "Searching Wikipedia",
                    message: "Matching titles, summaries, and context for \"\(searchCoordinator.searchText)\".",
                    detail: "Discover search",
                    symbol: "magnifyingglass",
                    tone: .accent,
                    rowCount: 5
                )
            } else if searchCoordinator.searchResults.isEmpty && !searchCoordinator.isLoading {
                Text("No matching articles")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(searchCoordinator.searchResults.prefix(20)) { result in
                        let rowKey = "search:\(result.id):\(ReadStateSync.normalizedTitle(result.title))"
                        let isSaved = savedTitles.contains(ReadStateSync.normalizedTitle(result.title))
                        DiscoverSearchResultRow(result: result, isSaved: isSaved) {
                            onOpen(result, SystemBridge.isCommandPressed)
                        }
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
                        if result.id != searchCoordinator.searchResults.prefix(20).last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
