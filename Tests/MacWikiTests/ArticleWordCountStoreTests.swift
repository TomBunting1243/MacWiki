import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ArticleWordCountStoreTests {
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
            batchSize: 1
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
            batchSize: 1
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
            batchSize: 1
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
        for _ in 0..<200 {
            if !store.isLoading {
                return
            }
            await Task.yield()
        }
        Issue.record("Word-count store never became idle")
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
