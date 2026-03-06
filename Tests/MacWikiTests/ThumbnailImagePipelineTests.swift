import AppKit
import Foundation
import Testing

@testable import MacWiki

struct ThumbnailImagePipelineTests {
    @Test func cachedResponsesBypassNetworkLoader() async {
        let url = URL(string: "https://example.com/cached.jpg")!
        let recorder = PipelineLoadRecorder()
        let cachedData = Data([0x01, 0x02, 0x03])
        let pipeline = ThumbnailImagePipeline(
            dataLoader: { request in
                await recorder.record(request.url)
                return Data([0x09])
            },
            cachedResponseLoader: { request in
                guard request.url == url else { return nil }
                return CachedURLResponse(
                    response: URLResponse(
                        url: url,
                        mimeType: "image/jpeg",
                        expectedContentLength: cachedData.count,
                        textEncodingName: nil
                    ),
                    data: cachedData
                )
            }
        )

        let result = await pipeline.loadImageData(for: url)

        #expect(result?.source == .cache)
        #expect(result?.data == cachedData)
        #expect(await recorder.urls() == [])
    }

    @Test func concurrentLoadsShareOneNetworkRequest() async {
        let url = URL(string: "https://example.com/network.jpg")!
        let recorder = PipelineLoadRecorder()
        let payload = Data([0x05, 0x06, 0x07])
        let pipeline = ThumbnailImagePipeline(
            dataLoader: { request in
                await recorder.record(request.url)
                try? await Task.sleep(for: .milliseconds(30))
                return payload
            },
            cachedResponseLoader: { _ in nil }
        )

        async let first = pipeline.loadImageData(for: url)
        async let second = pipeline.loadImageData(for: url)
        let results = await [first, second]

        #expect(results.compactMap(\.self).count == 2)
        #expect(results.allSatisfy { $0?.source == .network })
        #expect(results.allSatisfy { $0?.data == payload })
        #expect(await recorder.urls() == [url])
    }

    @MainActor
    @Test func decodedCacheEvictsLeastRecentlyUsedEntries() {
        let first = URL(string: "https://example.com/one.jpg")!
        let second = URL(string: "https://example.com/two.jpg")!
        let cache = DecodedThumbnailImageCache(maxEntries: 1)
        let firstKey = DecodedThumbnailImageKey(url: first, maxPixelSize: 64)
        let secondKey = DecodedThumbnailImageKey(url: second, maxPixelSize: 64)

        cache.store(NSImage(size: NSSize(width: 4, height: 4)), for: firstKey)
        cache.store(NSImage(size: NSSize(width: 4, height: 4)), for: secondKey)

        #expect(cache.image(for: firstKey) == nil)
        #expect(cache.image(for: secondKey) != nil)
    }

    @MainActor
    @Test func decodedCacheKeepsDistinctSizeVariantsForSameURL() {
        let url = URL(string: "https://example.com/shared.jpg")!
        let smallKey = DecodedThumbnailImageKey(url: url, maxPixelSize: 32)
        let largeKey = DecodedThumbnailImageKey(url: url, maxPixelSize: 96)
        let cache = DecodedThumbnailImageCache(maxEntries: 4)

        cache.store(NSImage(size: NSSize(width: 32, height: 32)), for: smallKey)
        cache.store(NSImage(size: NSSize(width: 96, height: 96)), for: largeKey)

        #expect(cache.image(for: smallKey)?.size.width == 32)
        #expect(cache.image(for: largeKey)?.size.width == 96)
    }

    @Test func decoderDownsamplesToRequestedMaximumPixelSize() {
        let data = TestThumbnailImageDataFactory.png(width: 400, height: 200)

        let decoded = ThumbnailImageDecoder.decode(data, maxPixelSize: 80)

        #expect(decoded?.cgImage.width == 80)
        #expect(decoded?.cgImage.height == 40)
    }

    @Test func decoderKeepsOriginalSizeWhenNoDownsampleIsRequested() {
        let data = TestThumbnailImageDataFactory.png(width: 160, height: 90)

        let decoded = ThumbnailImageDecoder.decode(data, maxPixelSize: 0)

        #expect(decoded?.cgImage.width == 160)
        #expect(decoded?.cgImage.height == 90)
    }
}

private actor PipelineLoadRecorder {
    private var loadedURLs: [URL] = []

    func record(_ url: URL?) {
        if let url {
            loadedURLs.append(url)
        }
    }

    func urls() -> [URL] {
        loadedURLs
    }
}

private enum TestThumbnailImageDataFactory {
    static func png(width: Int, height: Int) -> Data {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            fatalError("Failed to create bitmap test data")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            fatalError("Failed to create PNG test data")
        }
        return pngData
    }
}
