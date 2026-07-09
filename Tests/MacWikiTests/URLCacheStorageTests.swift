import Foundation
import Testing

@testable import MacWiki

struct URLCacheStorageTests {
    @Test func cacheDirectoryIsCreatedWithinMacWikiCaches() throws {
        let fileManager = FileManager.default
        let temporaryCachesDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MacWikiURLCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryCachesDirectory) }

        let directory = MacWikiURLCacheStorage.directoryURL(
            in: temporaryCachesDirectory,
            fileManager: fileManager
        )
        let expectedDirectory = temporaryCachesDirectory
            .appendingPathComponent("MacWiki", isDirectory: true)
            .appendingPathComponent("URLCache", isDirectory: true)

        #expect(directory == expectedDirectory)

        var isDirectory: ObjCBool = false
        #expect(fileManager.fileExists(atPath: expectedDirectory.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func appUsesExplicitURLCacheDirectoryOnMacOS() throws {
        let appSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent("Sources/MacWiki/App/MacWikiApp.swift"),
            encoding: .utf8
        )
        let configuration = sourceSection(
            appSource,
            startingAt: "private static func configureGlobalURLCache()",
            endingBefore: "private static func sanitizePersistedWindowAndSplitViewState()"
        )

        #expect(configuration.contains("MacWikiURLCacheStorage.systemDirectoryURL()"))
        #expect(configuration.contains("directory: directory"))
        #expect(!configuration.contains("diskPath:"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceSection(
        _ source: String,
        startingAt start: String,
        endingBefore end: String
    ) -> String {
        guard let startRange = source.range(of: start) else {
            return source
        }
        let remainder = source[startRange.lowerBound...]
        guard let endRange = remainder.range(of: end) else {
            return String(remainder)
        }
        return String(remainder[..<endRange.lowerBound])
    }
}
