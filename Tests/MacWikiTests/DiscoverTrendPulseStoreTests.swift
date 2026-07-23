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

    @Test func transientFailureRetriesOnceAndPublishesRecoveredPulse() async {
        let recorder = TrendPulseAttemptRecorder(failuresBeforeSuccess: 1)
        let store = DiscoverTrendPulseStore(
            batchSize: 1,
            automaticRetryLimit: 1,
            retrySleeper: { _ in },
            trendPulseLoader: { title, referenceDate in
                try await recorder.load(title: title, referenceDate: referenceDate)
            }
        )
        let result = searchResult("Recovered Article")

        store.queueLoad(results: [result], referenceDate: referenceDate)
        await waitUntilIdle(store)

        #expect(await recorder.attemptCount() == 2)
        #expect(store.pulse(for: result.title) != nil)
        #expect(!store.failedTitleKeys.contains(titleMatchKey(result.title)))
    }

    @Test func permanentFailureDoesNotSpendAutomaticRetryBudget() async {
        let recorder = TrendPulseAttemptRecorder(
            failuresBeforeSuccess: .max,
            failure: WikipediaService.WikipediaError.noResults
        )
        let store = DiscoverTrendPulseStore(
            batchSize: 1,
            automaticRetryLimit: 1,
            retrySleeper: { _ in },
            trendPulseLoader: { title, referenceDate in
                try await recorder.load(title: title, referenceDate: referenceDate)
            }
        )
        let result = searchResult("Unavailable Article")

        store.queueLoad(results: [result], referenceDate: referenceDate)
        await waitUntilIdle(store)

        #expect(await recorder.attemptCount() == 1)
        #expect(store.pulse(for: result.title) == nil)
        #expect(store.failedTitleKeys.contains(titleMatchKey(result.title)))
    }

    @Test func explicitRefreshReloadsUnchangedTargets() async {
        let recorder = TrendPulseAttemptRecorder()
        let store = DiscoverTrendPulseStore(
            batchSize: 1,
            retrySleeper: { _ in },
            trendPulseLoader: { title, referenceDate in
                try await recorder.load(title: title, referenceDate: referenceDate)
            }
        )
        let result = searchResult("Refreshable Article")

        store.queueLoad(
            results: [result],
            referenceDate: referenceDate,
            refreshGeneration: 0
        )
        await waitUntilIdle(store)
        store.queueLoad(
            results: [result],
            referenceDate: referenceDate,
            refreshGeneration: 1
        )
        await waitUntilIdle(store)

        #expect(await recorder.attemptCount() == 2)
        #expect(store.pulse(for: result.title) != nil)
    }

    @Test func successfulPopoverLoadCanRepairFailedRowState() async throws {
        let store = DiscoverTrendPulseStore(
            batchSize: 1,
            automaticRetryLimit: 0,
            retrySleeper: { _ in },
            trendPulseLoader: { _, _ in
                throw WikipediaService.WikipediaError.noResults
            }
        )
        let result = searchResult("Repairable Article")
        store.queueLoad(results: [result], referenceDate: referenceDate)
        await waitUntilIdle(store)
        #expect(store.failedTitleKeys.contains(titleMatchKey(result.title)))

        let repairedPulse = pulse(referenceDate: referenceDate)
        store.record(repairedPulse, for: result.title, referenceDate: referenceDate)

        #expect(store.pulse(for: result.title)?.latestViews == repairedPulse.latestViews)
        #expect(!store.failedTitleKeys.contains(titleMatchKey(result.title)))
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func searchResult(_ title: String) -> WikipediaService.SearchResult {
        WikipediaService.SearchResult(
            id: title,
            title: title,
            description: nil,
            thumbnailURL: nil
        )
    }

    private func pulse(referenceDate: Date) -> WikipediaService.TrendPulse {
        WikipediaService.TrendPulse(
            points: [1, 2, 3],
            latestViews: 3,
            previousViews: 2,
            windowStart: referenceDate.addingTimeInterval(-86_400),
            windowEnd: referenceDate
        )
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

private actor TrendPulseAttemptRecorder {
    private let failuresBeforeSuccess: Int
    private let failure: Error
    private var attempts = 0

    init(
        failuresBeforeSuccess: Int = 0,
        failure: Error = WikipediaService.WikipediaError.networkError(URLError(.timedOut))
    ) {
        self.failuresBeforeSuccess = failuresBeforeSuccess
        self.failure = failure
    }

    func load(
        title: String,
        referenceDate: Date
    ) throws -> WikipediaService.TrendPulse {
        attempts += 1
        if attempts <= failuresBeforeSuccess {
            throw failure
        }
        return WikipediaService.TrendPulse(
            points: [1, 2, 3],
            latestViews: 3,
            previousViews: 2,
            windowStart: referenceDate.addingTimeInterval(-86_400),
            windowEnd: referenceDate
        )
    }

    func attemptCount() -> Int {
        attempts
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
