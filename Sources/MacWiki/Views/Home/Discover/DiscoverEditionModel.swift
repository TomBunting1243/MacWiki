import Foundation
import Observation

/// Owns the asynchronous data pipeline for one Discover edition.
///
/// The view supplies disclosure and refresh intent; this model enforces the
/// load budgets and cancellation policy so the SwiftUI surface only composes
/// presentation and interaction state.
@Observable @MainActor
final class DiscoverEditionModel {
    let allTimeMostRead = DiscoverAllTimeMostReadStore()
    let todayMostRead = DiscoverTodayMostReadStore()
    let mostReadTrendPulse = DiscoverTrendPulseStore()
    let todayTrendPulse = DiscoverTrendPulseStore()
    let wordCounts = ArticleWordCountStore()
    let featuredSummary = DiscoverFeaturedSummaryStore()
    let visualContext = DiscoverVisualContextStore()

    func updateTodayMostRead(isExpanded: Bool, forceRefresh: Bool) {
        guard isExpanded else {
            todayMostRead.cancel()
            return
        }
        todayMostRead.queueLoad(forceRefresh: forceRefresh)
    }

    func updateAllTimeMostRead(
        showsMostRead: Bool,
        showsLongestReads: Bool,
        limit: Int
    ) {
        guard showsMostRead || showsLongestReads else {
            allTimeMostRead.cancel()
            return
        }
        allTimeMostRead.queueLoad(limit: limit)
    }

    func updateTodayTrendPulse(
        isExpanded: Bool,
        results: [WikipediaService.SearchResult],
        referenceDate: Date
    ) {
        guard isExpanded else {
            todayTrendPulse.cancel()
            return
        }
        todayTrendPulse.queueLoad(results: results, referenceDate: referenceDate)
    }

    func updateMostReadTrendPulse(
        isExpanded: Bool,
        results: [WikipediaService.SearchResult],
        referenceDate: Date
    ) {
        guard isExpanded else {
            mostReadTrendPulse.cancel()
            return
        }
        mostReadTrendPulse.queueLoad(results: results, referenceDate: referenceDate)
    }

    func updateWordCounts(
        isExpanded: Bool,
        results: [WikipediaService.SearchResult]
    ) {
        guard isExpanded else {
            wordCounts.cancel()
            return
        }
        wordCounts.queueLoad(results: results)
    }

    func updateFeaturedArticle(title: String?) {
        featuredSummary.queueLoad(featuredTitle: title)
        visualContext.queueLoad(featuredTitle: title)
    }

    func cancelAll() {
        todayMostRead.cancel()
        todayTrendPulse.cancel()
        allTimeMostRead.cancel()
        mostReadTrendPulse.cancel()
        wordCounts.cancel()
        featuredSummary.cancel()
        visualContext.cancel()
    }
}
