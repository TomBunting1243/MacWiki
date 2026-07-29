import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DiscoverAllTimeMostReadStoreTests {
    @Test func forceRefreshBypassesPopulatedStoreCacheAndReachesLoader() async {
        let recorder = AllTimeMostReadRequestRecorder()
        let referenceDate = Date(timeIntervalSince1970: 1_750_000_000)
        let fetchBudget = AllTimeMostReadFetchBudget(
            monthlyRequestBatchSize: 2,
            perMonthArticleLimit: 40,
            summaryRequestBatchSize: 3,
            summaryTargetMultiplier: 2,
            minimumSummaryTargetCount: 12
        )
        let store = DiscoverAllTimeMostReadStore(
            fetchBudget: fetchBudget,
            rankingLoader: { request in
                await recorder.load(request)
            }
        )

        store.queueLoad(limit: 1, referenceDate: referenceDate)
        await waitUntilIdle(store)

        store.queueLoad(limit: 1, referenceDate: referenceDate)
        await Task.yield()
        #expect(await recorder.requests().count == 1)

        store.queueLoad(
            limit: 1,
            referenceDate: referenceDate,
            forceRefresh: true
        )
        await waitUntilIdle(store)

        let requests = await recorder.requests()
        #expect(requests.count == 2)
        #expect(requests.map(\.forceRefresh) == [false, true])
        #expect(requests.allSatisfy { $0.fetchBudget == fetchBudget })
        #expect(store.entries.first?.totalViews == 2)
    }

    private func waitUntilIdle(_ store: DiscoverAllTimeMostReadStore) async {
        for _ in 0..<400 {
            if !store.isLoading {
                return
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("All-time most-read store never became idle")
    }
}

private actor AllTimeMostReadRequestRecorder {
    private var recordedRequests: [DiscoverAllTimeMostReadLoadRequest] = []

    func load(
        _ request: DiscoverAllTimeMostReadLoadRequest
    ) -> [WikipediaService.AllTimeMostReadEntry] {
        recordedRequests.append(request)
        let attempt = recordedRequests.count
        return [
            WikipediaService.AllTimeMostReadEntry(
                result: WikipediaService.SearchResult(
                    id: "ranked-\(attempt)",
                    title: "Ranked Article",
                    description: nil,
                    thumbnailURL: nil
                ),
                totalViews: attempt
            )
        ]
    }

    func requests() -> [DiscoverAllTimeMostReadLoadRequest] {
        recordedRequests
    }
}
