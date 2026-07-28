import Foundation
import Testing

@testable import MacWiki

struct URLCacheStorageTests {
    @Test func configuredCacheUsesMacWikiDirectoryAndExpectedCapacities() {
        let fileManager = FileManager.default
        let temporaryCachesDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacWikiURLCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryCachesDirectory) }

        let configuredCache = MacWikiURLCacheStorage.makeCache(
            in: temporaryCachesDirectory,
            fileManager: fileManager
        )
        let expectedDirectory = temporaryCachesDirectory
            .appendingPathComponent("MacWiki", isDirectory: true)
            .appendingPathComponent("URLCache", isDirectory: true)

        #expect(configuredCache.storageDirectoryURL == expectedDirectory)
        #expect(configuredCache.cache.memoryCapacity == 48 * 1024 * 1024)
        #expect(configuredCache.cache.diskCapacity == 240 * 1024 * 1024)

        var installedCache: URLCache?
        #expect(MacWikiURLCacheStorage.installSharedCache(configuredCache) {
            installedCache = $0
        })
        #expect(installedCache === configuredCache.cache)

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: expectedDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func cacheInstallationUsesTheExactFallbackCacheWhenDirectoryCreationFails() {
        let fallbackCache = URLCache(memoryCapacity: 1, diskCapacity: 2)
        let configuredCache = MacWikiURLCacheStorage.ConfiguredCache(
            cache: fallbackCache,
            storageDirectoryURL: nil
        )
        var installedCache: URLCache?

        let hasDedicatedStorage = MacWikiURLCacheStorage.installSharedCache(configuredCache) {
            installedCache = $0
        }

        #expect(!hasDedicatedStorage)
        #expect(installedCache === fallbackCache)
    }
}
