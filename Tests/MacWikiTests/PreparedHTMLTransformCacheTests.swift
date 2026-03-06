import Foundation
import Testing

@testable import MacWiki

struct PreparedHTMLTransformCacheTests {
    @Test func evictsOldestRewrittenEntriesWhenByteBudgetIsExceeded() {
        var cache = PreparedHTMLTransformCache(
            maxEntries: 4,
            maxTotalBytes: 10,
            maxEntryBytes: 10
        )

        cache.store(.rewritten("1234"), forKey: "a")
        cache.store(.rewritten("5678"), forKey: "b")
        cache.store(.rewritten("9012"), forKey: "c")

        #expect(cache.cachedEntry(forKey: "a") == nil)
        #expect(cache.cachedEntry(forKey: "b") == .rewritten("5678"))
        #expect(cache.cachedEntry(forKey: "c") == .rewritten("9012"))
        #expect(cache.totalBytes == 8)
    }

    @Test func oversizedRewrittenEntryIsSkippedButPassthroughStillCaches() {
        var cache = PreparedHTMLTransformCache(
            maxEntries: 4,
            maxTotalBytes: 20,
            maxEntryBytes: 5
        )

        cache.store(.rewritten("123456"), forKey: "too-large")
        #expect(cache.cachedEntry(forKey: "too-large") == nil)

        cache.store(.passthrough, forKey: "too-large")
        #expect(cache.cachedEntry(forKey: "too-large") == .passthrough)
        #expect(cache.totalBytes == 0)
    }
}
