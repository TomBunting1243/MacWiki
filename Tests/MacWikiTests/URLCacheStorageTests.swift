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

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: expectedDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}
