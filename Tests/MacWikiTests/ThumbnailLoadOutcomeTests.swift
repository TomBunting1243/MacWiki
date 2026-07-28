import Testing

@testable import MacWiki

struct ThumbnailLoadOutcomeTests {
    @Test func missingPipelineResultBecomesFailure() {
        let outcome = ThumbnailLoadOutcome<Int>.resolve(nil, isCancelled: false)

        guard case .failure = outcome else {
            Issue.record("A completed request without image data must leave the loading phase")
            return
        }
    }

    @Test func cancellationDoesNotPublishFailure() {
        let outcome = ThumbnailLoadOutcome.resolve(42, isCancelled: true)

        guard case .cancelled = outcome else {
            Issue.record("Cancellation must not replace the next request's presentation")
            return
        }
    }

    @Test func availablePipelineResultContinuesToDecoding() {
        let outcome = ThumbnailLoadOutcome.resolve(42, isCancelled: false)

        guard case .success(let value) = outcome else {
            Issue.record("Available image data must continue through the decode path")
            return
        }
        #expect(value == 42)
    }

    @Test func currentRequestCompletionCanPublish() {
        let policy = ThumbnailLoadPublicationPolicy(activeRequest: "current")

        #expect(policy.permitsPublication(for: "current", isCancelled: false))
    }

    @Test func staleRequestCompletionCannotPublish() {
        let policy = ThumbnailLoadPublicationPolicy(activeRequest: "current")

        #expect(!policy.permitsPublication(for: "stale", isCancelled: false))
    }

    @Test func cancelledRequestCompletionCannotPublish() {
        let policy = ThumbnailLoadPublicationPolicy(activeRequest: "current")

        #expect(!policy.permitsPublication(for: "current", isCancelled: true))
    }

    @Test func completionWithoutAnActiveRequestCannotPublish() {
        let policy = ThumbnailLoadPublicationPolicy<String>(activeRequest: nil)

        #expect(!policy.permitsPublication(for: "current", isCancelled: false))
    }
}
