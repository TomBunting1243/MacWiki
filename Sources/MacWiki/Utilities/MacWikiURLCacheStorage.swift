import Foundation

enum MacWikiURLCacheStorage {
    private static let appDirectoryName = "MacWiki"
    private static let cacheDirectoryName = "URLCache"

    static func systemDirectoryURL(fileManager: FileManager = .default) -> URL? {
        guard let cachesDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        else {
            return nil
        }

        return directoryURL(in: cachesDirectory, fileManager: fileManager)
    }

    static func directoryURL(
        in cachesDirectory: URL,
        fileManager: FileManager = .default
    ) -> URL? {
        let directory = cachesDirectory
            .appendingPathComponent(appDirectoryName, isDirectory: true)
            .appendingPathComponent(cacheDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            return directory
        } catch {
            return nil
        }
    }
}
