import Foundation
import Testing

@testable import MacWiki

struct DiscoverLoadBudgetRegressionTests {
    @Test func supplementalPlansCancelCollapsedWorkAndLoadExpandedWork() {
        #expect(DiscoverTodayMostReadLoadPlan(
            isExpanded: false,
            refreshGeneration: 0
        ).work == .cancel)
        #expect(DiscoverAllTimeMostReadLoadPlan(
            showsMostRead: false,
            showsLongestReads: false,
            requestedLimit: 48,
            refreshGeneration: 0
        ).work == .cancel)
        #expect(DiscoverTrendPulseLoadPlan(
            scope: .todayMostRead,
            isExpanded: false,
            feedDateKey: "2026/07/29",
            titleFingerprint: 1,
            refreshGeneration: 0
        ).work == .cancel)
        #expect(DiscoverWordCountLoadPlan(
            isExpanded: false,
            titleFingerprint: 1,
            refreshGeneration: 0
        ).work == .cancel)

        #expect(DiscoverTodayMostReadLoadPlan(
            isExpanded: true,
            refreshGeneration: 0
        ).work == .load)
        #expect(DiscoverAllTimeMostReadLoadPlan(
            showsMostRead: true,
            showsLongestReads: false,
            requestedLimit: 48,
            refreshGeneration: 0
        ).work == .load)
        #expect(DiscoverAllTimeMostReadLoadPlan(
            showsMostRead: false,
            showsLongestReads: true,
            requestedLimit: 48,
            refreshGeneration: 0
        ).work == .load)
        #expect(DiscoverTrendPulseLoadPlan(
            scope: .allTimeMostRead,
            isExpanded: true,
            feedDateKey: "2026/07/29",
            titleFingerprint: 1,
            refreshGeneration: 0
        ).work == .load)
        #expect(DiscoverWordCountLoadPlan(
            isExpanded: true,
            titleFingerprint: 1,
            refreshGeneration: 0
        ).work == .load)
    }

    @Test func initialThumbnailPlanPreservesPriorityDeduplicatesAndCapsURLs() {
        let budget = DiscoverFeedThumbnailPrefetchBudget.initialViewport
        #expect(budget.maximumURLCount == 10)
        #expect(budget.inTheNewsLimit == 4)
        #expect(budget.trendingLimit == 4)

        let urls = (0..<10).map { URL(fileURLWithPath: "/prefetch/\($0).jpg") }
        let plan = DiscoverFeedThumbnailPrefetchPlan(
            heroURL: urls[0],
            featuredImageURL: urls[1],
            inTheNewsURLs: [urls[0], nil, urls[2], urls[3], urls[9]],
            trendingURLs: [urls[3], urls[4], urls[5], urls[6], urls[8]],
            budget: DiscoverFeedThumbnailPrefetchBudget(
                maximumURLCount: 7,
                inTheNewsLimit: budget.inTheNewsLimit,
                trendingLimit: budget.trendingLimit
            )
        )

        #expect(plan.urls == Array(urls[0...6]))
    }

    @Test func supplementalStoresAndHistoricalRankingUseExplicitBudgets() {
        #expect(DiscoverTrendPulseLoadBudget.standard.concurrentRequestLimit == 4)
        #expect(DiscoverTrendPulseLoadBudget.standard.automaticRetryLimit == 8)
        #expect(ArticleWordCountLoadBudget.standard.concurrentRequestLimit == 6)

        let historicalBudget = AllTimeMostReadFetchBudget.standard
        #expect(historicalBudget.monthlyRequestBatchSize == 6)
        #expect(historicalBudget.perMonthArticleLimit == 180)
        #expect(historicalBudget.summaryRequestBatchSize == 6)
        #expect(historicalBudget.summaryTargetCount(
            requestedLimit: 10,
            availableCandidateCount: 200
        ) == 80)
        #expect(historicalBudget.summaryTargetCount(
            requestedLimit: 36,
            availableCandidateCount: 200
        ) == 108)
    }

    @Test func refreshGenerationChangesEveryTaskIdentityAndEnablesRetryPlans() {
        let initialToday = DiscoverTodayMostReadLoadPlan(
            isExpanded: true,
            refreshGeneration: 0
        )
        let refreshedToday = DiscoverTodayMostReadLoadPlan(
            isExpanded: true,
            refreshGeneration: 1
        )
        #expect(initialToday != refreshedToday)
        #expect(!initialToday.forceRefresh)
        #expect(refreshedToday.forceRefresh)

        let initialAllTime = DiscoverAllTimeMostReadLoadPlan(
            showsMostRead: true,
            showsLongestReads: true,
            requestedLimit: 48,
            refreshGeneration: 0
        )
        let refreshedAllTime = DiscoverAllTimeMostReadLoadPlan(
            showsMostRead: true,
            showsLongestReads: true,
            requestedLimit: 48,
            refreshGeneration: 1
        )
        #expect(initialAllTime != refreshedAllTime)
        #expect(!initialAllTime.forceRefresh)
        #expect(refreshedAllTime.forceRefresh)

        let initialPulse = DiscoverTrendPulseLoadPlan(
            scope: .allTimeMostRead,
            isExpanded: true,
            feedDateKey: "2026/07/29",
            titleFingerprint: 42,
            refreshGeneration: 0
        )
        let refreshedPulse = DiscoverTrendPulseLoadPlan(
            scope: .allTimeMostRead,
            isExpanded: true,
            feedDateKey: "2026/07/29",
            titleFingerprint: 42,
            refreshGeneration: 1
        )
        #expect(initialPulse != refreshedPulse)

        let initialWordCount = DiscoverWordCountLoadPlan(
            isExpanded: true,
            titleFingerprint: 42,
            refreshGeneration: 0
        )
        let refreshedWordCount = DiscoverWordCountLoadPlan(
            isExpanded: true,
            titleFingerprint: 42,
            refreshGeneration: 1
        )
        #expect(initialWordCount != refreshedWordCount)
        #expect(!initialWordCount.retriesFailedLoads)
        #expect(refreshedWordCount.retriesFailedLoads)

        #expect(DiscoverFeaturedArticleLoadPlan(
            title: "Ada Lovelace",
            refreshGeneration: 0
        ) != DiscoverFeaturedArticleLoadPlan(
            title: "Ada Lovelace",
            refreshGeneration: 1
        ))
    }
}
