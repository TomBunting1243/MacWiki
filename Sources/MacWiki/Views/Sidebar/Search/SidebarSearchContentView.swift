import SwiftUI

struct SidebarSearchContentView: View {
    let model: SidebarSearchSurfaceModel
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let onRetry: () -> Void
    let onOpenRow: (SidebarSearchRow, Bool) -> Void
    let onToggleRead: (SidebarSearchRow) -> Void

    var body: some View {
        switch model.displayState {
        case .results:
            SidebarSearchResultsView(
                model: model,
                allLists: allLists,
                allLabels: allLabels,
                allTags: allTags,
                onOpenRow: onOpenRow,
                onToggleRead: onToggleRead
            )
        case .error(let message):
            SidebarSearchStateView(
                title: "Search Unavailable",
                message: Text(verbatim: message),
                systemImage: "exclamationmark.triangle.fill",
                style: .quiet,
                actionTitle: "Try Again",
                action: onRetry
            )
        case .searching(let query):
            SidebarSearchLoadingRowsView(
                accessibilityLabel: "Searching Wikipedia for \(query)"
            )
        case .noQueryResults(let query):
            SidebarSearchStateView(
                title: "No Results",
                message: "No articles found for \"\(query)\"",
                systemImage: "sparkle.magnifyingglass"
            )
        case .noUnreadQueryResults:
            SidebarSearchStateView(
                title: "No Unread Matches",
                message: "Everything in these results is marked read.",
                systemImage: "checkmark.circle"
            )
        case .noFilteredResults:
            SidebarSearchStateView(
                title: "No Filtered Results",
                message: "Clear the active filters to show more articles.",
                systemImage: "line.3.horizontal.decrease.circle"
            )
        case .noUnreadFilteredResults:
            SidebarSearchStateView(
                title: "No Unread Filtered Results",
                message: "Everything in the filtered results is marked read.",
                systemImage: "checkmark.circle"
            )
        case .loadingTrending:
            SidebarSearchLoadingRowsView(
                accessibilityLabel: "Loading Top Reads"
            )
        case .emptyPrompt:
            SidebarSearchStateView(
                title: "Search Wikipedia",
                message: "Ask for a person, place, event, or idea.",
                systemImage: "sparkles"
            )
        case .noUnreadTrending:
            SidebarSearchStateView(
                title: "No Unread Results",
                message: "Everything in trending is marked read.",
                systemImage: "checkmark.circle"
            )
        }
    }
}
