import Foundation
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

    @Test func thumbnailViewPublishesOnlyForTheCurrentRequest() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Shared/CachedThumbnailImage.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("@State private var activeLoadRequest: LoadRequest?"))
        #expect(source.contains("guard activeLoadRequest == request, !Task.isCancelled else { return }"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
