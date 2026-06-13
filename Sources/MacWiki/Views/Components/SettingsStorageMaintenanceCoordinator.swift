import Foundation
import OSLog

private let storageMaintenanceLogger = Logger(subsystem: "com.macwiki", category: "storage-maintenance")

enum SettingsStorageAction: String, Identifiable {
    case clearMemory
    case clearTemporaryDisk
    case clearAllArticleCache
    case resetAllAppData

    var id: String { rawValue }

    var requiresConfirmation: Bool {
        switch self {
        case .clearMemory:
            false
        case .clearTemporaryDisk, .clearAllArticleCache, .resetAllAppData:
            true
        }
    }

    var confirmationTitle: String {
        switch self {
        case .clearMemory:
            "Clear Memory Cache?"
        case .clearTemporaryDisk:
            "Clear Temporary Disk Cache?"
        case .clearAllArticleCache:
            "Clear All Article Cache?"
        case .resetAllAppData:
            "Reset All App Data?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .clearMemory:
            "This removes in-memory article cache for the current app session."
        case .clearTemporaryDisk:
            "This removes non-pinned disk-cached articles. Saved, highlighted, and tagged articles remain cached."
        case .clearAllArticleCache:
            "This removes all article cache data, including pinned saved/highlighted/tagged entries."
        case .resetAllAppData:
            "This removes all local data: lists, saved articles, highlights, notes, labels, tags, reading progress, tabs, cache, and preferences. This action cannot be undone."
        }
    }

    var successMessage: String {
        switch self {
        case .clearMemory:
            "Memory cache cleared."
        case .clearTemporaryDisk:
            "Temporary disk cache cleared. Pinned article cache was preserved."
        case .clearAllArticleCache:
            "All article cache was cleared."
        case .resetAllAppData:
            "All local app data was reset."
        }
    }

    var confirmationButtonLabel: String {
        switch self {
        case .resetAllAppData:
            "Reset"
        default:
            "Clear"
        }
    }
}

struct SettingsStorageMaintenanceResult {
    let metrics: WikipediaService.CacheMetrics
    let statusMessage: String
}

enum SettingsStorageMaintenanceCoordinator {
    @MainActor
    static func perform(
        _ action: SettingsStorageAction,
        clearInMemoryArticleCache: () async -> Void,
        clearDiskArticleCache: (_ includePinned: Bool) async -> Void,
        clearCache: () async -> Void,
        cacheMetrics: () async -> WikipediaService.CacheMetrics,
        resetPersistedData: () async throws -> Void
    ) async -> SettingsStorageMaintenanceResult {
        var statusMessage = action.successMessage

        switch action {
        case .clearMemory:
            await clearInMemoryArticleCache()
        case .clearTemporaryDisk:
            await clearDiskArticleCache(false)
        case .clearAllArticleCache:
            await clearInMemoryArticleCache()
            await clearDiskArticleCache(true)
        case .resetAllAppData:
            do {
                await clearCache()
                try await resetPersistedData()
            } catch {
                storageMaintenanceLogger.error("Reset all app data failed: \(error.localizedDescription, privacy: .public)")
                statusMessage = "Reset failed. Please try again."
            }
        }

        return SettingsStorageMaintenanceResult(
            metrics: await cacheMetrics(),
            statusMessage: statusMessage
        )
    }
}
