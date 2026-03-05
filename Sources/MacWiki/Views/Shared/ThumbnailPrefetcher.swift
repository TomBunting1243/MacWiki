import Foundation

/// Warms `URLCache` so `AsyncImage` surfaces can feel instant on revisit.
///
/// This is intentionally simple: it doesn't decode images, it just ensures the network
/// payload is likely already in cache when the SwiftUI view asks for it.
actor ThumbnailPrefetcher {
    static let shared = ThumbnailPrefetcher()

    private let session: URLSession
    private var inFlight: Set<URL> = []

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 14
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    func prefetch(_ urls: [URL], maxConcurrent: Int = 6) async {
        let uniqueURLs = Array(Set(urls))
        guard !uniqueURLs.isEmpty else { return }

        var index = 0
        while index < uniqueURLs.count {
            let batchEnd = min(index + max(1, maxConcurrent), uniqueURLs.count)
            let batch = uniqueURLs[index..<batchEnd]

            await withTaskGroup(of: URL?.self) { group in
                for url in batch {
                    if inFlight.contains(url) { continue }

                    var request = URLRequest(url: url)
                    request.cachePolicy = .returnCacheDataElseLoad
                    if URLCache.shared.cachedResponse(for: request) != nil { continue }

                    inFlight.insert(url)
                    group.addTask { [session] in
                        var request = URLRequest(url: url)
                        request.cachePolicy = .returnCacheDataElseLoad
                        request.timeoutInterval = 10
                        _ = try? await session.data(for: request)
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
}

