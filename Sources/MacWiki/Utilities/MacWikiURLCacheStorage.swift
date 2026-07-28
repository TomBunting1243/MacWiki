import Foundation

enum MacWikiURLCacheStorage {
    struct ConfiguredCache {
        let cache: URLCache
        let storageDirectoryURL: URL?
    }

    private static let appDirectoryName = "MacWiki"
    private static let cacheDirectoryName = "URLCache"
    private static let memoryCapacity = 48 * 1024 * 1024
    private static let diskCapacity = 240 * 1024 * 1024

    static func makeSystemCache(fileManager: FileManager = .default) -> ConfiguredCache {
        configuredCache(
            storageDirectoryURL: systemDirectoryURL(fileManager: fileManager)
        )
    }

    static func makeCache(
        in cachesDirectory: URL,
        fileManager: FileManager = .default
    ) -> ConfiguredCache {
        configuredCache(
            storageDirectoryURL: directoryURL(
                in: cachesDirectory,
                fileManager: fileManager
            )
        )
    }

    /// Installs the app's configured cache and reports whether its dedicated
    /// on-disk directory was available. A missing directory is non-fatal:
    /// `URLCache` then uses the platform's default storage location.
    @discardableResult
    static func installSystemCache() -> Bool {
        installSharedCache(makeSystemCache())
    }

    @discardableResult
    static func installSharedCache(
        _ configuredCache: ConfiguredCache,
        installer: (URLCache) -> Void = { URLCache.shared = $0 }
    ) -> Bool {
        installer(configuredCache.cache)
        return configuredCache.storageDirectoryURL != nil
    }

    private static func systemDirectoryURL(fileManager: FileManager) -> URL? {
        guard let cachesDirectory = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        else {
            return nil
        }

        return directoryURL(in: cachesDirectory, fileManager: fileManager)
    }

    private static func directoryURL(
        in cachesDirectory: URL,
        fileManager: FileManager
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

    private static func configuredCache(storageDirectoryURL: URL?) -> ConfiguredCache {
        ConfiguredCache(
            cache: URLCache(
                memoryCapacity: memoryCapacity,
                diskCapacity: diskCapacity,
                directory: storageDirectoryURL
            ),
            storageDirectoryURL: storageDirectoryURL
        )
    }
}
