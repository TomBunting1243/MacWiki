import Foundation
import SwiftUI

extension DiscoverFeedSections {
    var allTimeMostReadStore: DiscoverAllTimeMostReadStore {
        editionModel.allTimeMostRead
    }

    var todayMostReadStore: DiscoverTodayMostReadStore {
        editionModel.todayMostRead
    }

    var trendPulseStore: DiscoverTrendPulseStore {
        editionModel.mostReadTrendPulse
    }

    var todayTrendPulseStore: DiscoverTrendPulseStore {
        editionModel.todayTrendPulse
    }

    var wordCountStore: ArticleWordCountStore {
        editionModel.wordCounts
    }

    var featuredSummaryStore: DiscoverFeaturedSummaryStore {
        editionModel.featuredSummary
    }

    var visualContextStore: DiscoverVisualContextStore {
        editionModel.visualContext
    }

    var isCompactLayout: Bool {
        responsiveLayout.isCompact
    }

    var sectionSpacing: CGFloat {
        responsiveLayout.feedSectionSpacing
    }

    var heroImageHeight: CGFloat {
        responsiveLayout.heroImageHeight
    }

    var leadStoryTitleLineLimit: Int {
        responsiveLayout.leadStoryTitleLineLimit
    }

    var leadStoryDescriptionLineLimit: Int {
        responsiveLayout.leadStoryDescriptionLineLimit
    }

    var inTheNewsRailLimit: Int {
        responsiveLayout.inTheNewsRailLimit
    }

    var hasTimeCapsuleDetails: Bool {
        !primaryTimelineEvents.isEmpty || !feed.didYouKnow.isEmpty
    }

    var newsBriefingLimit: Int {
        responsiveLayout.newsBriefingLimit
    }

    var allTimeMostReadLimit: Int {
        responsiveLayout.allTimeMostReadLimit
    }

    var playlistRowLimit: Int {
        responsiveLayout.playlistRowLimit
    }

    var allTimeMostReadLoadLimit: Int {
        max(allTimeMostReadLimit * 3, 48)
    }

    var todayMostReadLimit: Int {
        responsiveLayout.todayMostReadLimit
    }

    var allTimeMostReadEntries: [WikipediaService.AllTimeMostReadEntry] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLimit))
    }

    var todayMostReadItems: [WikipediaService.SearchResult] {
        Array(todayMostReadStore.results.prefix(todayMostReadLimit))
    }

    var allTimeMostReadByTitleKey: [String: WikipediaService.AllTimeMostReadEntry] {
        allTimeMostReadStore.entries.reduce(into: [:]) { result, entry in
            let key = ReadStateSync.normalizedTitle(entry.result.title)
            guard !key.isEmpty else { return }
            result[key] = entry
        }
    }

    var rankedMostReadItems: [WikipediaService.SearchResult] {
        allTimeMostReadEntries.map(\.result)
    }

    var playlistMostReadItems: [WikipediaService.SearchResult] {
        Array(rankedMostReadItems.prefix(playlistRowLimit))
    }

    /// A zero-cost editorial preview assembled from content the primary
    /// Discover feed already owns. The collapsed collection cards remain
    /// useful without starting the expensive historical ranking pipeline.
    var editorialCollectionPreviewItems: [WikipediaService.SearchResult] {
        DiscoverCollectionPreviewPolicy.editorialItems(
            featured: feed.featuredArticle,
            todayMostRead: todayMostReadItems,
            inTheNews: feed.inTheNews,
            trending: feed.trending,
            limit: min(playlistRowLimit, 6)
        )
    }

    var mostReadPreviewItems: [WikipediaService.SearchResult] {
        playlistMostReadItems.isEmpty ? editorialCollectionPreviewItems : playlistMostReadItems
    }

    var trendPulseItems: [WikipediaService.SearchResult] {
        var items: [WikipediaService.SearchResult] = []
        if let featuredArticle = feed.featuredArticle {
            items.append(featuredArticle)
        }
        items.append(contentsOf: playlistMostReadItems)
        return items
    }

    var allTimeMostReadLoadKey: String {
        "refresh:\(refreshGeneration)|\(allTimeMostReadLoadLimit)|most-read:\(isMostReadCollectionExpanded)|longest:\(isLongestReadsCollectionExpanded)"
    }

    var todayMostReadLoadKey: String {
        "today-most-read:\(refreshGeneration)|expanded:\(isTodayMostReadExpanded)"
    }

    var todayTrendPulseLoadKey: Int {
        titleFingerprint(
            todayMostReadItems.map(\.title),
            seeds: [
                AnyHashable(feed.dateKey),
                AnyHashable("today-most-read-pulse"),
                AnyHashable(refreshGeneration),
                AnyHashable(isTodayMostReadExpanded)
            ]
        )
    }

    var trendPulseLoadKey: Int {
        titleFingerprint(
            trendPulseItems.map(\.title),
            seeds: [
                AnyHashable(feed.dateKey),
                AnyHashable("playlist-most-read-pulse"),
                AnyHashable(refreshGeneration),
                AnyHashable(isMostReadCollectionExpanded)
            ]
        )
    }

    var featuredArticleTitle: String? {
        feed.featuredArticle?.title
    }

    var featuredArticleLoadKey: String {
        "refresh:\(refreshGeneration)|title:\(featuredArticleTitle ?? "")"
    }

    var featuredTeaserText: String? {
        guard let featuredArticleTitle else { return nil }
        return featuredSummaryStore.teaser(for: featuredArticleTitle)
    }

    var isFeaturedTeaserLoading: Bool {
        featuredSummaryStore.isLoading && (featuredTeaserText == nil)
    }

    var trendReferenceDate: Date {
        Self.featuredFeedDateFormatter.date(from: feed.dateKey) ?? Date()
    }

    var mostReadPulseReferenceDate: Date {
        trendReferenceDate
    }

    var timeMachineDisplayDateLabel: String {
        return feed.dateLabel
    }

    func titleFingerprint<S: Sequence>(
        _ titles: S,
        seeds: [AnyHashable] = []
    ) -> Int where S.Element == String {
        var hasher = Hasher()
        for seed in seeds {
            hasher.combine(seed)
        }
        for title in titles {
            hasher.combine(ReadStateSync.normalizedTitle(title))
        }
        return hasher.finalize()
    }

    var todayMostReadSubtitle: String {
        DiscoverEditionCopy.todayMostReadColumnSubtitle
    }

    var playlistMostReadSubtitle: String {
        DiscoverEditionCopy.allTimeMostReadSubtitle
    }

    var playlistLongestSubtitle: String {
        DiscoverEditionCopy.longestReadsSubtitle
    }

    var mostReadCollectionMeta: String {
        if allTimeMostReadStore.isLoading { return "Updating ranking" }
        if !allTimeMostReadEntries.isEmpty { return "\(allTimeMostReadEntries.count) ranked" }
        return isMostReadCollectionExpanded ? "Ranking unavailable" : "Editorial preview"
    }

    var longestCollectionMeta: String {
        if allTimeMostReadStore.isLoading || wordCountStore.isLoading { return "Measuring length" }
        if !rankedLongestResults.isEmpty { return "\(rankedLongestResults.count) candidates" }
        return isLongestReadsCollectionExpanded ? "Length data unavailable" : "Editorial preview"
    }

    var todayMostReadMeta: String {
        todayMostReadStore.isLoading ? "Refreshing" : "\(todayMostReadItems.count) articles today"
    }

    var todayMostReadPreviewTitles: [String] {
        Array(todayMostReadItems.prefix(3).map(\.title))
    }

    var mostReadPreviewTitles: [String] {
        Array(mostReadPreviewItems.prefix(3).map(\.title))
    }

    var longestReadsPreviewTitles: [String] {
        Array(longestPreviewItems.prefix(3).map(\.title))
    }

    var remainingNewsItems: [WikipediaService.SearchResult] {
        feed.inTheNews
    }

    var primaryTimelineEvents: [WikipediaService.DiscoverFeed.OnThisDayEvent] {
        if !feed.onThisDaySelected.isEmpty {
            return Array(feed.onThisDaySelected.prefix(8))
        }
        return Array(feed.onThisDay.prefix(8))
    }

    var leadTimelineEvent: WikipediaService.DiscoverFeed.OnThisDayEvent? {
        primaryTimelineEvents.first
    }

    var supportingTimelineEvents: [WikipediaService.DiscoverFeed.OnThisDayEvent] {
        Array(primaryTimelineEvents.dropFirst())
    }

    var hasTimeMachineDetails: Bool {
        return !feed.onThisDayBirths.isEmpty || !feed.onThisDayDeaths.isEmpty || !feed.holidays.isEmpty
    }

    var hasTimeMachineSurface: Bool {
        hasTimeMachineDetails
    }

    var longestReadCandidates: [WikipediaService.SearchResult] {
        Array(allTimeMostReadStore.entries.prefix(allTimeMostReadLoadLimit).map(\.result))
    }

    var wordCountLoadKey: Int {
        titleFingerprint(
            longestReadCandidates.map(\.title),
            seeds: [
                AnyHashable("longest-word-count"),
                AnyHashable(refreshGeneration),
                AnyHashable(isLongestReadsCollectionExpanded)
            ]
        )
    }

    var longestReadItems: [DiscoverLongestReadEntry] {
        let enriched = longestReadCandidates.compactMap { result -> DiscoverLongestReadEntry? in
            guard let wordCount = wordCountStore.wordCount(for: result.title), wordCount > 0 else {
                return nil
            }
            return DiscoverLongestReadEntry(result: result, wordCount: wordCount)
        }

        let sorted = enriched.sorted { lhs, rhs in
            if lhs.wordCount == rhs.wordCount {
                return lhs.result.title.localizedCaseInsensitiveCompare(rhs.result.title) == .orderedAscending
            }
            return lhs.wordCount > rhs.wordCount
        }

        return Array(sorted.prefix(playlistRowLimit))
    }

    var longestFallbackItems: [WikipediaService.SearchResult] {
        Array(longestReadCandidates.prefix(min(playlistRowLimit, 6)))
    }

    var rankedLongestResults: [WikipediaService.SearchResult] {
        if !longestReadItems.isEmpty {
            return longestReadItems.map(\.result)
        }
        return longestFallbackItems
    }

    var longestPreviewItems: [WikipediaService.SearchResult] {
        rankedLongestResults.isEmpty ? editorialCollectionPreviewItems : rankedLongestResults
    }

    var keyboardMostReadResults: [WikipediaService.SearchResult] {
        isMostReadCollectionExpanded ? playlistMostReadItems : mostReadPreviewItems
    }

    var keyboardLongestResults: [WikipediaService.SearchResult] {
        isLongestReadsCollectionExpanded ? rankedLongestResults : longestPreviewItems
    }

    var collectionsKeyboardContext: DiscoverCollectionsKeyboardContext {
        DiscoverCollectionsKeyboardContext(
            mostReadCount: keyboardMostReadResults.count,
            longestCount: keyboardLongestResults.count
        )
    }

    var visibleKeyboardLanes: [DiscoverCollectionLane] {
        collectionsKeyboardContext.visibleLanes
    }

    var collectionsFocusDataKey: Int {
        var hasher = Hasher()
        hasher.combine(
            titleFingerprint(
                keyboardMostReadResults.map(\.title),
                seeds: [AnyHashable("keyboard-most-read")]
            )
        )
        hasher.combine(
            titleFingerprint(
                keyboardLongestResults.map(\.title),
                seeds: [AnyHashable("keyboard-longest")]
            )
        )
        return hasher.finalize()
    }

    var canOpenFocusedCollectionItem: Bool {
        guard currentCollectionsKeyboardState().isActive else { return false }
        return focusedCollectionResult != nil
    }
}
