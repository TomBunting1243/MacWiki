import Foundation

struct SidebarDiscoverMostReadSelection: Equatable, Sendable {
    enum ContentKind: Equatable, Sendable {
        case ranked
        case editorialFallback

        var sectionTitle: LocalizedStringResource {
            switch self {
            case .ranked:
                "Most Read"
            case .editorialFallback:
                "Discover Picks"
            }
        }
    }

    let items: [WikipediaService.SearchResult]
    let contentKind: ContentKind

    var sectionTitle: LocalizedStringResource {
        contentKind.sectionTitle
    }

}

enum SidebarDiscoverMostReadPolicy {
    static func selection(
        from feed: WikipediaService.DiscoverFeed,
        limit: Int = 24
    ) -> SidebarDiscoverMostReadSelection {
        let primaryTimeline = feed.onThisDaySelected.isEmpty
            ? feed.onThisDay
            : feed.onThisDaySelected

        return selection(
            rankedItems: feed.trending,
            editorialGroups: [
                feed.inTheNews,
                feed.newsStories.flatMap(\.links),
                primaryTimeline.compactMap(\.article),
                feed.didYouKnow.compactMap(\.article),
            ],
            limit: limit
        )
    }

    static func selection(
        rankedItems: [WikipediaService.SearchResult],
        editorialGroups: [[WikipediaService.SearchResult]],
        limit: Int = 24
    ) -> SidebarDiscoverMostReadSelection {
        guard limit > 0 else {
            return SidebarDiscoverMostReadSelection(items: [], contentKind: .ranked)
        }

        let ranked = uniqueItems(in: [rankedItems], limit: limit)
        if !ranked.isEmpty {
            return SidebarDiscoverMostReadSelection(items: ranked, contentKind: .ranked)
        }

        let editorial = uniqueItems(in: editorialGroups, limit: limit)
        let contentKind: SidebarDiscoverMostReadSelection.ContentKind = editorial.isEmpty
            ? .ranked
            : .editorialFallback
        return SidebarDiscoverMostReadSelection(items: editorial, contentKind: contentKind)
    }

    private static func uniqueItems(
        in groups: [[WikipediaService.SearchResult]],
        limit: Int
    ) -> [WikipediaService.SearchResult] {
        var uniqueItems: [WikipediaService.SearchResult] = []
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()

        for group in groups {
            for item in group {
                let normalizedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedTitle = ReadStateSync.normalizedTitle(item.title)
                guard !normalizedID.isEmpty, !normalizedTitle.isEmpty else { continue }
                guard !seenIDs.contains(normalizedID), !seenTitles.contains(normalizedTitle) else {
                    continue
                }

                seenIDs.insert(normalizedID)
                seenTitles.insert(normalizedTitle)
                uniqueItems.append(item)
                if uniqueItems.count == limit {
                    return uniqueItems
                }
            }
        }

        return uniqueItems
    }
}

/// De-duplicated article destinations represented by a Discover edition. The
/// complete inventory drives the honest edition count; the rendered-row subset
/// bounds metadata hydration to rows that actually consume that metadata.
enum SidebarDiscoverArticleInventory {
    static func articles(
        in feed: WikipediaService.DiscoverFeed
    ) -> [WikipediaService.SearchResult] {
        let primaryTimeline = feed.onThisDaySelected.isEmpty
            ? feed.onThisDay
            : feed.onThisDaySelected
        let groups: [[WikipediaService.SearchResult]] = [
            feed.featuredArticle.map { [$0] } ?? [],
            feed.trending,
            feed.newsStories.flatMap(\.links),
            feed.inTheNews,
            primaryTimeline.compactMap(\.article),
            feed.onThisDayBirths.compactMap(\.article),
            feed.onThisDayDeaths.compactMap(\.article),
            feed.holidays.compactMap(\.article),
            feed.didYouKnow.compactMap(\.article),
        ]

        return uniqueArticles(in: groups)
    }

    static func renderedArticleRows(
        in feed: WikipediaService.DiscoverFeed
    ) -> [WikipediaService.SearchResult] {
        let mostReadSelection = SidebarDiscoverMostReadPolicy.selection(from: feed)
        return uniqueArticles(in: [
            feed.featuredArticle.map { [$0] } ?? [],
            mostReadSelection.items,
            Array(feed.inTheNews.prefix(12)),
        ])
    }

    private static func uniqueArticles(
        in groups: [[WikipediaService.SearchResult]]
    ) -> [WikipediaService.SearchResult] {
        var results: [WikipediaService.SearchResult] = []
        var seenIDs = Set<String>()
        var seenTitles = Set<String>()
        for item in groups.joined() {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = ReadStateSync.normalizedTitle(item.title)
            guard !id.isEmpty, !title.isEmpty else { continue }
            guard seenIDs.insert(id).inserted, seenTitles.insert(title).inserted else {
                continue
            }
            results.append(item)
        }
        return results
    }
}

struct SidebarDiscoverPulseLoadIdentity: Hashable, Sendable {
    let dateKey: String?
    let normalizedTitles: [String]
    let refreshGeneration: Int

    init(dateKey: String?, titles: [String], refreshGeneration: Int) {
        self.dateKey = dateKey
        normalizedTitles = titles.map(ReadStateSync.normalizedTitle)
        self.refreshGeneration = refreshGeneration
    }
}
