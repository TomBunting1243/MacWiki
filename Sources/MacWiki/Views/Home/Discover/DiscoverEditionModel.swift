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

    func updateTodayMostRead(_ plan: DiscoverTodayMostReadLoadPlan) {
        guard plan.work == .load else {
            todayMostRead.cancel()
            return
        }
        todayMostRead.queueLoad(forceRefresh: plan.forceRefresh)
    }

    func performTodayMostReadFailureAction(_ plan: DiscoverTodayMostReadFailureActionPlan) {
        todayMostRead.queueLoad(forceRefresh: plan.forceRefresh)
    }

    func updateAllTimeMostRead(_ plan: DiscoverAllTimeMostReadLoadPlan) {
        guard plan.work == .load else {
            allTimeMostRead.cancel()
            return
        }
        allTimeMostRead.queueLoad(
            limit: plan.requestedLimit,
            forceRefresh: plan.forceRefresh
        )
    }

    func updateTodayTrendPulse(
        _ plan: DiscoverTrendPulseLoadPlan,
        results: [WikipediaService.SearchResult],
        referenceDate: Date
    ) {
        guard plan.work == .load else {
            todayTrendPulse.cancel()
            return
        }
        todayTrendPulse.queueLoad(
            results: results,
            referenceDate: referenceDate,
            refreshGeneration: plan.refreshGeneration
        )
    }

    func updateMostReadTrendPulse(
        _ plan: DiscoverTrendPulseLoadPlan,
        results: [WikipediaService.SearchResult],
        referenceDate: Date
    ) {
        guard plan.work == .load else {
            mostReadTrendPulse.cancel()
            return
        }
        mostReadTrendPulse.queueLoad(
            results: results,
            referenceDate: referenceDate,
            refreshGeneration: plan.refreshGeneration
        )
    }

    func updateWordCounts(
        _ plan: DiscoverWordCountLoadPlan,
        results: [WikipediaService.SearchResult]
    ) {
        guard plan.work == .load else {
            wordCounts.cancel()
            return
        }
        wordCounts.queueLoad(results: results, retryFailed: plan.retriesFailedLoads)
    }

    func updateFeaturedArticle(_ plan: DiscoverFeaturedArticleLoadPlan) {
        featuredSummary.queueLoad(featuredTitle: plan.title)
        visualContext.queueLoad(featuredTitle: plan.title)
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
