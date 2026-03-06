import Foundation
import Testing

@testable import MacWiki

struct ThumbnailPrefetcherTests {
    @Test func prefetchPreservesFirstSeenOrderAndSkipsCachedURLs() async {
        let recorder = PrefetchRequestRecorder()
        let first = URL(string: "https://example.com/first.jpg")!
        let cached = URL(string: "https://example.com/cached.jpg")!
        let third = URL(string: "https://example.com/third.jpg")!

        let prefetcher = ThumbnailPrefetcher(
            dataLoader: { request in
                if let url = request.url {
                    await recorder.record(url)
                }
            },
            cachedResponseLoader: { request in
                guard request.url == cached else { return nil }
                return CachedURLResponse(
                    response: URLResponse(
                        url: cached,
                        mimeType: "image/jpeg",
                        expectedContentLength: 3,
                        textEncodingName: nil
                    ),
                    data: Data([0x01, 0x02, 0x03])
                )
            },
            recentAttemptCooldown: 60
        )

        await prefetcher.prefetch([first, cached, third, first], maxConcurrent: 1)

        #expect(await recorder.urls() == [first, third])
    }

    @Test func prefetchThrottlesRepeatedAttemptsUntilCooldownExpires() async {
        let recorder = PrefetchRequestRecorder()
        let clock = TestDateProviderBox(date: Date(timeIntervalSinceReferenceDate: 100))
        let url = URL(string: "https://example.com/repeat.jpg")!

        let prefetcher = ThumbnailPrefetcher(
            dataLoader: { request in
                if let url = request.url {
                    await recorder.record(url)
                }
            },
            cachedResponseLoader: { _ in nil },
            dateProvider: { clock.date },
            recentAttemptCooldown: 60
        )

        await prefetcher.prefetch([url], maxConcurrent: 1)
        await prefetcher.prefetch([url], maxConcurrent: 1)

        clock.date = Date(timeIntervalSinceReferenceDate: 150)
        await prefetcher.prefetch([url], maxConcurrent: 1)

        clock.date = Date(timeIntervalSinceReferenceDate: 161)
        await prefetcher.prefetch([url], maxConcurrent: 1)

        #expect(await recorder.urls() == [url, url])
    }
}

private actor PrefetchRequestRecorder {
    private var recordedURLs: [URL] = []

    func record(_ url: URL) {
        recordedURLs.append(url)
    }

    func urls() -> [URL] {
        recordedURLs
    }
}

private final class TestDateProviderBox: @unchecked Sendable {
    var date: Date

    init(date: Date) {
        self.date = date
    }
}
