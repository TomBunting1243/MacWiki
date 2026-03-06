import Foundation
import Testing

@testable import MacWiki

@MainActor
struct PerformanceMetricsStoreTests {
    @Test func summariesPersistAcrossStoreReloads() throws {
        let suiteName = "MacWiki.PerformanceMetricsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = PerformanceMetricsStore(
            userDefaults: defaults,
            storageKey: "samples",
            maxSamplesPerKind: 8
        )
        store.record(kind: .search, durationMs: 120, detail: "chars=4 results=8")
        store.record(kind: .search, durationMs: 240, detail: "chars=8 results=12")

        let summary = store.summary(for: .search)
        #expect(summary?.sampleCount == 2)
        #expect(abs((summary?.averageDurationMs ?? 0) - 180) < 0.001)
        #expect(abs((summary?.lastDurationMs ?? 0) - 240) < 0.001)

        let restored = PerformanceMetricsStore(
            userDefaults: defaults,
            storageKey: "samples",
            maxSamplesPerKind: 8
        )
        let restoredSummary = restored.summary(for: .search)
        #expect(restoredSummary?.sampleCount == 2)
        #expect(abs((restoredSummary?.averageDurationMs ?? 0) - 180) < 0.001)

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func retentionIsScopedPerMetricKind() throws {
        let suiteName = "MacWiki.PerformanceMetricsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = PerformanceMetricsStore(
            userDefaults: defaults,
            storageKey: "samples",
            maxSamplesPerKind: 2
        )
        store.record(kind: .search, durationMs: 100, detail: "first")
        store.record(kind: .search, durationMs: 200, detail: "second")
        store.record(kind: .search, durationMs: 300, detail: "third")
        store.record(kind: .readerOpen, durationMs: 640, detail: "reader")

        let searchSummary = store.summary(for: .search)
        #expect(searchSummary?.sampleCount == 2)
        #expect(searchSummary?.lastDetail == "third")
        #expect(abs((searchSummary?.bestDurationMs ?? 0) - 200) < 0.001)
        #expect(abs((searchSummary?.worstDurationMs ?? 0) - 300) < 0.001)

        let readerSummary = store.summary(for: .readerOpen)
        #expect(readerSummary?.sampleCount == 1)
        #expect(readerSummary?.lastDetail == "reader")

        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func samplesPersistUnderPerKindStorageKeys() throws {
        let suiteName = "MacWiki.PerformanceMetricsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Failed to create isolated defaults suite")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = PerformanceMetricsStore(
            userDefaults: defaults,
            storageKey: "samples",
            maxSamplesPerKind: 4
        )
        store.record(kind: .search, durationMs: 100, detail: "search")
        store.record(kind: .readerOpen, durationMs: 200, detail: "reader")

        #expect(defaults.data(forKey: "samples.search") != nil)
        #expect(defaults.data(forKey: "samples.readerOpen") != nil)
        #expect(defaults.data(forKey: "samples") == nil)

        defaults.removePersistentDomain(forName: suiteName)
    }
}
