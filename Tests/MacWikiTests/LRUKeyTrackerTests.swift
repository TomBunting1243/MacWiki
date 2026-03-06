import Testing

@testable import MacWiki

struct LRUKeyTrackerTests {
    @Test func touchingExistingKeyMovesItToMostRecentPosition() {
        var tracker = LRUKeyTracker<String>()

        tracker.touch("alpha")
        tracker.touch("beta")
        tracker.touch("alpha")

        #expect(tracker.orderedKeys == ["beta", "alpha"])
    }

    @Test func trimEvictsOldestKeysFirst() {
        var tracker = LRUKeyTracker<String>()

        tracker.touch("alpha")
        tracker.touch("beta")
        tracker.touch("gamma")

        let evicted = tracker.trim(to: 2)

        #expect(evicted == ["alpha"])
        #expect(tracker.orderedKeys == ["beta", "gamma"])
    }

    @Test func removeDropsKeyWithoutDisturbingOtherOrder() {
        var tracker = LRUKeyTracker<String>()

        tracker.touch("alpha")
        tracker.touch("beta")
        tracker.touch("gamma")
        tracker.remove("beta")

        #expect(tracker.orderedKeys == ["alpha", "gamma"])
    }
}
