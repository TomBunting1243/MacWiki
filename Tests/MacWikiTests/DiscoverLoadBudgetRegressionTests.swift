import Foundation
import Testing

struct DiscoverLoadBudgetRegressionTests {
    @Test func collapsedCollectionsDoNotStartSupplementalDiscoveryWork() throws {
        let source = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverEditionModel.swift"
        )

        #expect(source.contains("guard showsMostRead || showsLongestReads else"))
        #expect(source.contains("guard isExpanded else"))
        #expect(source.contains("allTimeMostRead.cancel()"))
        #expect(source.contains("mostReadTrendPulse.cancel()"))
        #expect(source.contains("wordCounts.cancel()"))
    }

    @Test func supplementalNetworkWorkHasExplicitConcurrencyAndPrefetchBudgets() throws {
        let feedStore = try repositorySource(
            "Sources/MacWiki/Views/Shared/DiscoverFeedStore.swift"
        )
        let trendStore = try repositorySource(
            "Sources/MacWiki/Views/Shared/DiscoverTrendPulseStore.swift"
        )
        let trendingService = try repositorySource(
            "Sources/MacWiki/Services/WikipediaService+DiscoverTrending.swift"
        )

        #expect(feedStore.contains("let initialPrefetchBudget = 10"))
        #expect(feedStore.contains("feed.inTheNews.prefix(4)"))
        #expect(feedStore.contains("feed.trending.prefix(4)"))
        #expect(trendStore.contains("batchSize: Int = 4"))
        #expect(trendStore.contains("batchStart + batchSize"))
        #expect(trendStore.contains("automaticRetryLimit: Int = 8"))
        #expect(trendStore.contains("Self.isTransient(error)"))
        #expect(trendingService.contains("let monthlyFetchBatchSize = 6"))
        #expect(trendingService.contains("let summaryFetchBatchSize = 6"))
    }

    @Test func explicitRefreshRetriesEverySupplementalDiscoveryPipeline() throws {
        let sections = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeedSections.swift"
        )
        let policy = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeedDataPolicy.swift"
        )
        let wordCounts = try repositorySource(
            "Sources/MacWiki/Views/Shared/ArticleWordCountStore.swift"
        )

        #expect(sections.contains(".task(id: featuredArticleLoadKey)"))
        #expect(sections.contains("retryFailed: refreshGeneration > 0"))
        #expect(policy.contains("refresh:\\(refreshGeneration)"))
        #expect(policy.components(separatedBy: "AnyHashable(refreshGeneration)").count >= 4)
        #expect(wordCounts.contains("retryFailed: Bool = false"))
        #expect(wordCounts.contains("attemptedTitleKeys.subtract(validKeys)"))
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
