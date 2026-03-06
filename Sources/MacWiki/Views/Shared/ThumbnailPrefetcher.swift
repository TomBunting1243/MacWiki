import Foundation

/// Warms `URLCache` so `AsyncImage` surfaces can feel instant on revisit.
///
/// This is intentionally simple: it doesn't decode images, it just ensures the network
/// payload is likely already in cache when the SwiftUI view asks for it.
actor ThumbnailPrefetcher {
    static let shared = ThumbnailPrefetcher()

    typealias DataLoader = @Sendable (URLRequest) async -> Void
    typealias CachedResponseLoader = @Sendable (URLRequest) -> CachedURLResponse?
    typealias DateProvider = @Sendable () -> Date

    private let dataLoader: DataLoader
    private let cachedResponseLoader: CachedResponseLoader
    private let dateProvider: DateProvider
    private let recentAttemptCooldown: TimeInterval
    private let maxRememberedURLs: Int
    private var inFlight: Set<URL> = []
    private var recentAttemptDates: [URL: Date] = [:]
    private var recentAttemptOrder = LRUKeyTracker<URL>()

    init(
        dataLoader: DataLoader? = nil,
        cachedResponseLoader: CachedResponseLoader? = nil,
        dateProvider: @escaping DateProvider = Date.init,
        recentAttemptCooldown: TimeInterval = 10 * 60,
        maxRememberedURLs: Int = 512
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 14
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        let session = URLSession(configuration: configuration)
        self.dataLoader = dataLoader ?? { request in
            _ = try? await session.data(for: request)
        }
        self.cachedResponseLoader = cachedResponseLoader ?? { request in
            URLCache.shared.cachedResponse(for: request)
        }
        self.dateProvider = dateProvider
        self.recentAttemptCooldown = max(0, recentAttemptCooldown)
        self.maxRememberedURLs = max(0, maxRememberedURLs)
    }

    func prefetch(_ urls: [URL], maxConcurrent: Int = 6) async {
        let uniqueURLs = deduplicatedURLsPreservingOrder(from: urls)
        guard !uniqueURLs.isEmpty else { return }
        let now = dateProvider()

        var index = 0
        while index < uniqueURLs.count {
            let batchEnd = min(index + max(1, maxConcurrent), uniqueURLs.count)
            let batch = uniqueURLs[index..<batchEnd]

            await withTaskGroup(of: URL?.self) { group in
                for url in batch {
                    if inFlight.contains(url) { continue }

                    var request = URLRequest(url: url)
                    request.cachePolicy = .returnCacheDataElseLoad
                    if cachedResponseLoader(request) != nil { continue }
                    if shouldThrottlePrefetch(for: url, now: now) { continue }

                    inFlight.insert(url)
                    rememberAttempt(for: url, at: now)
                    group.addTask { [dataLoader] in
                        var request = URLRequest(url: url)
                        request.cachePolicy = .returnCacheDataElseLoad
                        request.timeoutInterval = 10
                        await dataLoader(request)
                        return url
                    }
                }

                for await completedURL in group {
                    if let completedURL {
                        inFlight.remove(completedURL)
                    }
                }
            }

            index = batchEnd
        }
    }

    private func shouldThrottlePrefetch(for url: URL, now: Date) -> Bool {
        guard let attemptedAt = recentAttemptDates[url] else { return false }
        return now.timeIntervalSince(attemptedAt) < recentAttemptCooldown
    }

    private func rememberAttempt(for url: URL, at date: Date) {
        recentAttemptDates[url] = date
        recentAttemptOrder.touch(url)
        for evictedURL in recentAttemptOrder.trim(to: maxRememberedURLs) {
            recentAttemptDates.removeValue(forKey: evictedURL)
        }
    }

    private func deduplicatedURLsPreservingOrder(from urls: [URL]) -> [URL] {
        var seen = Set<URL>()
        var deduplicated: [URL] = []
        deduplicated.reserveCapacity(urls.count)

        for url in urls where seen.insert(url).inserted {
            deduplicated.append(url)
        }

        return deduplicated
    }
}
