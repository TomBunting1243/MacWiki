import Testing

@testable import MacWiki

struct AllTimeMostReadCachePolicyTests {
    @Test func insufficientCacheIsNotReusable() {
        #expect(
            AllTimeMostReadCachePolicy.reusablePrefixCount(
                cachedCount: 47,
                requestedLimit: 48
            ) == nil
        )
    }

    @Test func sufficientCacheReturnsRequestedPrefixCount() {
        #expect(
            AllTimeMostReadCachePolicy.reusablePrefixCount(
                cachedCount: 80,
                requestedLimit: 48
            ) == 48
        )
        #expect(
            AllTimeMostReadCachePolicy.reusablePrefixCount(
                cachedCount: 48,
                requestedLimit: 48
            ) == 48
        )
    }

    @Test func requestedLimitIsClampedToSupportedRange() {
        #expect(AllTimeMostReadCachePolicy.clampedLimit(0) == 1)
        #expect(AllTimeMostReadCachePolicy.clampedLimit(36) == 36)
        #expect(AllTimeMostReadCachePolicy.clampedLimit(81) == 80)

        #expect(
            AllTimeMostReadCachePolicy.reusablePrefixCount(
                cachedCount: 80,
                requestedLimit: 500
            ) == 80
        )
    }
}
