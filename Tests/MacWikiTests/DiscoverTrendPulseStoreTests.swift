import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DiscoverTrendPulseStoreTests {
    @Test func queueLoadBoundsConcurrentPulseRequests() async {
        let recorder = TrendPulseConcurrencyRecorder()
        let store = DiscoverTrendPulseStore(
            batchSize: 4,
            trendPulseLoader: { title, referenceDate in
                await recorder.begin(title)
                try await Task.sleep(for: .milliseconds(12))
                await recorder.end()
                return WikipediaService.TrendPulse(
                    points: [1, 2, 3],
                    latestViews: 3,
                    previousViews: 2,
                    windowStart: referenceDate.addingTimeInterval(-86_400),
                    windowEnd: referenceDate
                )
            }
        )
        let results = (0..<13).map { index in
            WikipediaService.SearchResult(
                id: "\(index)",
                title: "Article \(index)",
                description: nil,
                thumbnailURL: nil
            )
        }

        store.queueLoad(results: results, referenceDate: Date(timeIntervalSince1970: 1_700_000_000))
        await waitUntilIdle(store)

        #expect(await recorder.requestCount() == results.count)
        #expect(await recorder.peakConcurrency() <= 4)
        #expect(results.allSatisfy { store.pulse(for: $0.title) != nil })
        #expect(store.batchPublicationCountForCurrentRequest == 4)
    }

    private func waitUntilIdle(_ store: DiscoverTrendPulseStore) async {
        for _ in 0..<400 {
            if !store.isLoading {
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Trend-pulse store never became idle")
    }
}

private actor TrendPulseConcurrencyRecorder {
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
