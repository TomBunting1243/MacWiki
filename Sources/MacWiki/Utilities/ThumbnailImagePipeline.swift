import AppKit
import Foundation
@preconcurrency import ImageIO

actor ThumbnailImagePipeline {
    static let shared = ThumbnailImagePipeline()

    struct LoadResult: Sendable {
        enum Source: Sendable {
            case cache
            case network
        }

        let data: Data
        let source: Source
    }

    typealias DataLoader = @Sendable (URLRequest) async -> Data?
    typealias CachedResponseLoader = @Sendable (URLRequest) -> CachedURLResponse?

    private let dataLoader: DataLoader
    private let cachedResponseLoader: CachedResponseLoader
    private var inFlightLoads: [URL: Task<LoadResult?, Never>] = [:]

    init(
        dataLoader: DataLoader? = nil,
        cachedResponseLoader: CachedResponseLoader? = nil
    ) {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 14
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6

        let session = URLSession(configuration: configuration)
        self.dataLoader = dataLoader ?? { request in
            do {
                let (data, _) = try await session.data(for: request)
                return data
            } catch {
                return nil
            }
        }
        self.cachedResponseLoader = cachedResponseLoader ?? { request in
            URLCache.shared.cachedResponse(for: request)
        }
    }

    func loadImageData(for url: URL) async -> LoadResult? {
        let request = Self.request(for: url)
        if let cachedResponse = cachedResponseLoader(request),
           !cachedResponse.data.isEmpty {
            return LoadResult(data: cachedResponse.data, source: .cache)
        }

        if let inFlight = inFlightLoads[url] {
            return await inFlight.value
        }

        let task = Task<LoadResult?, Never> { [dataLoader] in
            let request = Self.request(for: url)
            guard let data = await dataLoader(request), !data.isEmpty else {
                return nil
            }
            return LoadResult(data: data, source: .network)
        }
        inFlightLoads[url] = task

        let result = await task.value
        inFlightLoads[url] = nil
        return result
    }

    private static func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 10
        return request
    }
}

struct DecodedThumbnailImageKey: Hashable, Sendable {
    let url: URL
    let maxPixelSize: Int
}

enum ThumbnailImageDecoder {
    struct CGImageBox: @unchecked Sendable {
        let cgImage: CGImage
    }

    static func decode(_ data: Data, maxPixelSize: Int) -> CGImageBox? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let sanitizedMaxPixelSize = max(0, maxPixelSize)
        let baseOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceShouldCacheImmediately: false
        ]

        let cgImage: CGImage?
        if sanitizedMaxPixelSize > 0 {
            var thumbnailOptions = baseOptions
            thumbnailOptions[kCGImageSourceCreateThumbnailFromImageAlways] = true
            thumbnailOptions[kCGImageSourceCreateThumbnailWithTransform] = true
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = sanitizedMaxPixelSize
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        } else {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, baseOptions as CFDictionary)
        }

        guard let cgImage else { return nil }
        return CGImageBox(cgImage: cgImage)
    }
}

@MainActor
final class DecodedThumbnailImageCache {
    static let shared = DecodedThumbnailImageCache()

    private let maxEntries: Int
    private var imageByKey: [DecodedThumbnailImageKey: NSImage] = [:]
    private var order = LRUKeyTracker<DecodedThumbnailImageKey>()

    init(maxEntries: Int = 192) {
        self.maxEntries = max(0, maxEntries)
    }

    func image(for key: DecodedThumbnailImageKey) -> NSImage? {
        guard let image = imageByKey[key] else { return nil }
        order.touch(key)
        return image
    }

    func store(_ image: NSImage, for key: DecodedThumbnailImageKey) {
        imageByKey[key] = image
        order.touch(key)
        for evictedKey in order.trim(to: maxEntries) {
            imageByKey.removeValue(forKey: evictedKey)
        }
    }

    func removeAll() {
        imageByKey.removeAll()
        order.removeAll()
    }
}
