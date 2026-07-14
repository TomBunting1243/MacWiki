import Foundation

@MainActor
enum DiscoverCollectionPreviewPolicy {
    static func editorialItems(
        featured: WikipediaService.SearchResult?,
        todayMostRead: [WikipediaService.SearchResult],
        inTheNews: [WikipediaService.SearchResult],
        trending: [WikipediaService.SearchResult],
        limit: Int = 6
    ) -> [WikipediaService.SearchResult] {
        guard limit > 0 else { return [] }

        var candidates: [WikipediaService.SearchResult] = []
        if let featured {
            candidates.append(featured)
        }
        candidates.append(contentsOf: todayMostRead)
        candidates.append(contentsOf: inTheNews)
        candidates.append(contentsOf: trending)

        var seenTitleKeys: Set<String> = []
        var result: [WikipediaService.SearchResult] = []
        result.reserveCapacity(min(limit, candidates.count))
        for candidate in candidates {
            let titleKey = ReadStateSync.normalizedTitle(candidate.title)
            guard !titleKey.isEmpty, seenTitleKeys.insert(titleKey).inserted else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
