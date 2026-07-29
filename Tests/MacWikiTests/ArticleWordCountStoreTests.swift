import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ArticleWordCountStoreTests {
    @Test func typedLoadBudgetBoundsConcurrentMetadataRequests() async {
        let recorder = WordCountConcurrencyRecorder()
        let loadBudget = ArticleWordCountLoadBudget(concurrentRequestLimit: 2)
        let store = ArticleWordCountStore(
            pageMetadataLoader: { title in
                await recorder.begin(title)
                try await Task.sleep(for: .milliseconds(12))
                await recorder.end()
                return WikipediaService.PageMetadata(wordCount: 500)
            },
            loadBudget: loadBudget
        )
        let results = (0..<7).map { searchResult("Article \($0)") }

        store.queueLoad(results: results)
        await waitUntilIdle(store)

        #expect(await recorder.requestCount() == results.count)
        #expect(await recorder.peakConcurrency() <= loadBudget.concurrentRequestLimit)
        #expect(results.allSatisfy { store.wordCount(for: $0.title) == 500 })
    }

    @Test func queueLoadDeduplicatesSkipsKnownTitlesAndCachesResults() async {
        let recorder = RequestedTitleRecorder()
        let responses = [
            "Ada Lovelace": 1_250,
            "Grace Hopper": 980,
            "Alan Turing": 1_500
        ]
        let store = ArticleWordCountStore(
            pageMetadataLoader: { title in
                await recorder.record(title)
                return WikipediaService.PageMetadata(wordCount: responses[title] ?? 0)
            },
            loadBudget: ArticleWordCountLoadBudget(concurrentRequestLimit: 1)
        )

        store.queueLoad(
            results: [
                searchResult("Ada Lovelace"),
                searchResult("Ada Lovelace"),
                searchResult("Alan Turing"),
                searchResult("Grace Hopper")
            ],
            limit: 2,
            skippingTitles: ["Alan Turing"]
        )
        await waitUntilIdle(store)

        #expect(await recorder.titles() == ["Ada Lovelace", "Grace Hopper"])
        #expect(store.wordCount(for: "Ada Lovelace") == 1_250)
        #expect(store.wordCount(for: "Grace Hopper") == 980)
        #expect(store.wordCount(for: "Alan Turing") == nil)
    }

    @Test func failedLoadsAreRetriedOnlyAfterTitleSetChanges() async {
        let recorder = RequestedTitleRecorder()
        let store = ArticleWordCountStore(
            pageMetadataLoader: { title in
                await recorder.record(title)
                if title == "Broken Article" {
                    throw TestLoaderError.failed
                }
                return WikipediaService.PageMetadata(wordCount: 640)
            },
            loadBudget: ArticleWordCountLoadBudget(concurrentRequestLimit: 1)
        )

        let brokenResults = [searchResult("Broken Article")]
        store.queueLoad(results: brokenResults)
        await waitUntilIdle(store)

        store.queueLoad(results: brokenResults)
        await waitUntilIdle(store)

        #expect(await recorder.titles() == ["Broken Article"])

        store.queueLoad(results: [searchResult("Working Article")])
        await waitUntilIdle(store)
        store.queueLoad(results: brokenResults)
        await waitUntilIdle(store)

        #expect(await recorder.titles() == ["Broken Article", "Working Article", "Broken Article"])
    }

    @Test func explicitRefreshRetriesFailedTitlesWithoutDiscardingCachedCounts() async {
        let recorder = RequestedTitleRecorder()
        let store = ArticleWordCountStore(
            pageMetadataLoader: { title in
                await recorder.record(title)
                if title == "Broken Article" {
                    throw TestLoaderError.failed
                }
                return WikipediaService.PageMetadata(wordCount: 640)
            },
            loadBudget: ArticleWordCountLoadBudget(concurrentRequestLimit: 1)
        )
        let results = [
            searchResult("Working Article"),
            searchResult("Broken Article")
        ]

        store.queueLoad(results: results)
        await waitUntilIdle(store)
        store.queueLoad(results: results, retryFailed: true)
        await waitUntilIdle(store)

        #expect(
            await recorder.titles()
                == ["Working Article", "Broken Article", "Broken Article"]
        )
        #expect(store.wordCount(for: "Working Article") == 640)
        #expect(store.wordCount(for: "Broken Article") == nil)
    }

    private func searchResult(_ title: String) -> WikipediaService.SearchResult {
        WikipediaService.SearchResult(
            id: title,
            title: title,
            description: nil,
            thumbnailURL: nil
        )
    }

    private func waitUntilIdle(_ store: ArticleWordCountStore) async {
        for _ in 0..<400 {
            if !store.isLoading {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Word-count store never became idle")
    }
}

private actor WordCountConcurrencyRecorder {
    private var requestedTitles: [String] = []
    private var activeCount = 0
    private var maximumActiveCount = 0

    func begin(_ title: String) {
        requestedTitles.append(title)
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
    }

    func end() {
        activeCount -= 1
    }

    func requestCount() -> Int {
        requestedTitles.count
    }

    func peakConcurrency() -> Int {
        maximumActiveCount
    }
}

private actor RequestedTitleRecorder {
    private var requestedTitles: [String] = []

    func record(_ title: String) {
        requestedTitles.append(title)
    }

    func titles() -> [String] {
        requestedTitles
    }
}

private enum TestLoaderError: Error {
    case failed
}
