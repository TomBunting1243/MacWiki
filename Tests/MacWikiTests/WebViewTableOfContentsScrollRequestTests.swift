import Testing

@testable import MacWiki

struct WebViewTableOfContentsScrollRequestTests {
    @Test func successfulCurrentRequestPublishesReachedSection() throws {
        let tracker = WebViewTableOfContentsScrollRequestTracker()
        let request = try #require(
            tracker.begin(sectionID: "history", articleTitle: "Ada", contentRevision: 10)
        )

        let completion = tracker.finish(
            request,
            didReachTarget: true,
            pendingSectionID: "history",
            currentArticleTitle: "Ada",
            currentContentRevision: 10
        )

        #expect(completion == .succeeded(sectionID: "history"))
        #expect(tracker.activeRequest == nil)
    }

    @Test func failedJavaScriptResultNeverPublishesSelection() throws {
        let tracker = WebViewTableOfContentsScrollRequestTracker()
        let request = try #require(
            tracker.begin(sectionID: "missing", articleTitle: "Ada", contentRevision: 10)
        )

        let completion = tracker.finish(
            request,
            didReachTarget: false,
            pendingSectionID: "missing",
            currentArticleTitle: "Ada",
            currentContentRevision: 10
        )

        #expect(completion == .failed(sectionID: "missing"))
    }

    @Test func rapidSecondRequestMakesFirstCompletionStale() throws {
        let tracker = WebViewTableOfContentsScrollRequestTracker()
        let first = try #require(
            tracker.begin(sectionID: "history", articleTitle: "Ada", contentRevision: 10)
        )
        let second = try #require(
            tracker.begin(sectionID: "legacy", articleTitle: "Ada", contentRevision: 10)
        )

        #expect(
            tracker.finish(
                first,
                didReachTarget: true,
                pendingSectionID: "legacy",
                currentArticleTitle: "Ada",
                currentContentRevision: 10
            ) == .ignored
        )
        #expect(tracker.activeRequest == second)
        #expect(
            tracker.finish(
                second,
                didReachTarget: true,
                pendingSectionID: "legacy",
                currentArticleTitle: "Ada",
                currentContentRevision: 10
            ) == .succeeded(sectionID: "legacy")
        )
    }

    @Test func articleSwitchCannotAcceptOldCompletion() throws {
        let tracker = WebViewTableOfContentsScrollRequestTracker()
        let request = try #require(
            tracker.begin(sectionID: "history", articleTitle: "Ada", contentRevision: 10)
        )

        #expect(
            tracker.finish(
                request,
                didReachTarget: true,
                pendingSectionID: "history",
                currentArticleTitle: "Grace",
                currentContentRevision: 11
            ) == .ignored
        )
    }

    @Test func duplicateViewUpdateDoesNotLaunchSameRequestTwice() {
        let tracker = WebViewTableOfContentsScrollRequestTracker()

        #expect(tracker.begin(sectionID: "history", articleTitle: "Ada", contentRevision: 10) != nil)
        #expect(tracker.begin(sectionID: "history", articleTitle: "Ada", contentRevision: 10) == nil)
    }
}
