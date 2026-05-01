import Foundation

enum SidebarSearchReadFilter: Hashable {
    case all
    case unread
}

enum SidebarSearchSortMode: String, CaseIterable, Hashable {
    case relevance = "Relevance"
    case title = "Title"
    case articleLength = "Length"
}

enum SidebarSearchSourceKind: String, Hashable {
    case query
    case trending

    var sectionTitle: String {
        switch self {
        case .query:
            return "Results"
        case .trending:
            return "Top Reads"
        }
    }
}

struct SidebarSearchPageViewsPopoverPayload {
    let rowID: String
    let title: String
}

@MainActor
struct SidebarSearchRow: Identifiable {
    let id: String
    let result: WikipediaService.SearchResult
    let article: Article
    let hydratedMetadata: ArticleMetadataHydrationSnapshot?
    let savedArticle: SavedArticle?
    let label: Label?
    let tags: [Tag]
    let isRead: Bool
    let readingProgress: Double
    let isCurrent: Bool
    let resolvedWordCount: Int?
}

@MainActor
struct SidebarSearchVisibleSnapshot {
    static let empty = SidebarSearchVisibleSnapshot(
        sourceKind: .trending,
        rows: [],
        sourceCount: 0,
        scopedCount: 0,
        scopedReadCount: 0,
        scopedUnreadCount: 0,
        visibleReadCount: 0,
        visibleUnreadCount: 0
    )

    let sourceKind: SidebarSearchSourceKind
    let rows: [SidebarSearchRow]
    let sourceCount: Int
    let scopedCount: Int
    let scopedReadCount: Int
    let scopedUnreadCount: Int
    let visibleReadCount: Int
    let visibleUnreadCount: Int

    var sectionTitle: String {
        sourceKind.sectionTitle
    }

    var visibleTitles: [String] {
        rows.map(\.article.title)
    }
}

enum SidebarSearchDisplayState: Equatable {
    case results
    case error(String)
    case searching(String)
    case noQueryResults(String)
    case noUnreadQueryResults
    case noFilteredResults
    case noUnreadFilteredResults
    case loadingTrending
    case emptyPrompt
    case noUnreadTrending
}
