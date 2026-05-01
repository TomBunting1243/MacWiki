import Foundation
import Testing

@testable import MacWiki

@MainActor
struct SettingsStorageMaintenanceCoordinatorTests {
    @Test func clearAllArticleCacheClearsMemoryThenPinnedDiskAndRefreshesMetrics() async {
        let recorder = SettingsStorageMaintenanceRecorder()
        let expectedMetrics = cacheMetrics(full: 1, fast: 2, disk: 3, pinned: 1)

        let result = await SettingsStorageMaintenanceCoordinator.perform(
            .clearAllArticleCache,
            clearInMemoryArticleCache: {
                await recorder.record("clear-memory")
            },
            clearDiskArticleCache: { includePinned in
                await recorder.record("clear-disk-\(includePinned)")
            },
            clearCache: {
                await recorder.record("clear-cache")
            },
            cacheMetrics: {
                await recorder.record("metrics")
                return expectedMetrics
            },
            resetPersistedData: {
                await recorder.record("reset")
            }
        )

        #expect(await recorder.snapshot() == ["clear-memory", "clear-disk-true", "metrics"])
        #expect(result.metrics.fullArticleEntries == expectedMetrics.fullArticleEntries)
        #expect(result.statusMessage == SettingsStorageAction.clearAllArticleCache.successMessage)
    }

    @Test func resetAllAppDataClearsCacheBeforeResettingPersistedState() async {
        let recorder = SettingsStorageMaintenanceRecorder()

        let result = await SettingsStorageMaintenanceCoordinator.perform(
            .resetAllAppData,
            clearInMemoryArticleCache: {
                await recorder.record("clear-memory")
            },
            clearDiskArticleCache: { includePinned in
                await recorder.record("clear-disk-\(includePinned)")
            },
            clearCache: {
                await recorder.record("clear-cache")
            },
            cacheMetrics: {
                await recorder.record("metrics")
                return cacheMetrics(full: 0, fast: 0, disk: 0, pinned: 0)
            },
            resetPersistedData: {
                await recorder.record("reset")
            }
        )

        #expect(await recorder.snapshot() == ["clear-cache", "reset", "metrics"])
        #expect(result.statusMessage == SettingsStorageAction.resetAllAppData.successMessage)
    }

    @Test func resetFailureStillRefreshesMetricsAndReturnsFriendlyStatus() async {
        let recorder = SettingsStorageMaintenanceRecorder()

        let result = await SettingsStorageMaintenanceCoordinator.perform(
            .resetAllAppData,
            clearInMemoryArticleCache: {
                await recorder.record("clear-memory")
            },
            clearDiskArticleCache: { includePinned in
                await recorder.record("clear-disk-\(includePinned)")
            },
            clearCache: {
                await recorder.record("clear-cache")
            },
            cacheMetrics: {
                await recorder.record("metrics")
                return cacheMetrics(full: 5, fast: 1, disk: 2, pinned: 1)
            },
            resetPersistedData: {
                await recorder.record("reset")
                throw SettingsStorageMaintenanceTestError.resetFailed
            }
        )

        #expect(await recorder.snapshot() == ["clear-cache", "reset", "metrics"])
        #expect(result.statusMessage == "Reset failed. Please try again.")
    }

    private func cacheMetrics(
        full: Int,
        fast: Int,
        disk: Int,
        pinned: Int
    ) -> WikipediaService.CacheMetrics {
        WikipediaService.CacheMetrics(
            fullArticleEntries: full,
            fullArticleBytes: full * 100,
            fastArticleEntries: fast,
            fastArticleBytes: fast * 50,
            diskArticleEntries: disk,
            diskArticleBytes: disk * 250,
            pinnedArticleEntries: pinned
        )
    }
}

private actor SettingsStorageMaintenanceRecorder {
    private var calls: [String] = []

    func record(_ call: String) {
        calls.append(call)
    }

    func snapshot() -> [String] {
        calls
    }
}

private enum SettingsStorageMaintenanceTestError: Error {
    case resetFailed
}
