import Foundation
import Testing

@testable import MacWiki

@MainActor
@Suite(.serialized)
struct HighlightRehydrateRequestTests {
    @Test func buildsRequestFromHighlightAnchorData() {
        let highlight = Highlight(
            text: "important passage",
            articleTitle: "Rehydrate",
            elementPath: "main[1]/p[2]",
            startOffset: 12,
            length: 17,
            contextBefore: "before ",
            contextAfter: " after",
            color: .blue
        )

        let request = AppState.HighlightRehydrateRequest(highlight: highlight)

        #expect(request.id == highlight.id)
        #expect(request.text == "important passage")
        #expect(request.cssColor == HighlightColor.blue.cssColor)
        #expect(request.elementPath == "main[1]/p[2]")
        #expect(request.startOffset == 12)
        #expect(request.contextBefore == "before ")
        #expect(request.contextAfter == " after")
    }

    @Test func buildsRequestWithEmptyContextWhenHighlightHasNoContext() {
        let highlight = Highlight(
            text: "short",
            articleTitle: "Rehydrate",
            startOffset: 0,
            length: 5
        )

        let request = AppState.HighlightRehydrateRequest(highlight: highlight)

        #expect(request.contextBefore == "")
        #expect(request.contextAfter == "")
        #expect(request.elementPath == "")
        #expect(request.startOffset == 0)
    }

    @Test func snapshotRequestPreservesTheDOMAnchor() {
        let highlight = Highlight(
            text: "anchored passage",
            articleTitle: "Rehydrate",
            elementPath: "main[1]/section[3]/p[2]",
            startOffset: 7,
            length: 16
        )

        let request = AppState.HighlightRehydrateRequest(
            highlight: InspectorHighlightSnapshot(highlight: highlight)
        )

        #expect(request.elementPath == "main[1]/section[3]/p[2]")
        #expect(request.startOffset == 7)
    }

    @MainActor
    @Test func webRestorationUsesTheDOMAnchorForADuplicatePassage() async throws {
        let harness = try await makeHarness()
        let highlight = Highlight(
            text: Self.duplicatePassage,
            articleTitle: "Rehydrate",
            elementPath: "section[2]/p[1]",
            startOffset: Self.secondContextBefore.count,
            length: Self.duplicatePassage.count,
            contextBefore: Self.firstContextBefore,
            contextAfter: Self.firstContextAfter,
            color: .blue
        )

        let observation = try await retry(
            AppState.HighlightRehydrateRequest(highlight: highlight),
            in: harness
        )

        #expect(observation.duplicateCount == 2)
        #expect(observation.success)
        #expect(observation.ownerID == "second-occurrence")
        #expect(observation.text == Self.duplicatePassage)
    }

    @MainActor
    @Test func webRestorationFallsBackToContextWhenTheStoredPathIsInvalid() async throws {
        let harness = try await makeHarness()
        let highlight = Highlight(
            text: Self.duplicatePassage,
            articleTitle: "Rehydrate",
            elementPath: "section[99]/p[1]",
            startOffset: 0,
            length: Self.duplicatePassage.count,
            contextBefore: Self.secondContextBefore,
            contextAfter: Self.secondContextAfter,
            color: .pink
        )

        let observation = try await retry(
            AppState.HighlightRehydrateRequest(highlight: highlight),
            in: harness
        )

        #expect(observation.duplicateCount == 2)
        #expect(observation.success)
        #expect(observation.ownerID == "second-occurrence")
        #expect(observation.text == Self.duplicatePassage)
    }

    @MainActor
    private func makeHarness() async throws -> ReaderWebKitHarness {
        let harness = ReaderWebKitHarness(
            size: CGSize(width: 640, height: 480),
            injectReaderStyle: false,
            injectWebViewScript: true
        )
        try await harness.loadHTML(Self.duplicatePassageFixture)
        try await harness.waitUntil("typeof window.retryHighlight === 'function'")
        return harness
    }

    @MainActor
    private func retry(
        _ request: AppState.HighlightRehydrateRequest,
        in harness: ReaderWebKitHarness
    ) async throws -> RetryObservation {
        let payload: [String: Any] = [
            "id": request.id.uuidString,
            "text": request.text,
            "color": request.cssColor,
            "elementPath": request.elementPath,
            "startOffset": request.startOffset,
            "contextBefore": request.contextBefore,
            "contextAfter": request.contextAfter
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = try #require(String(data: data, encoding: .utf8))
        let resultJSON = try await harness.evaluateString(
            """
            (function () {
                const payload = \(json);
                const success = window.retryHighlight(payload);
                const stored = window._macwikiHighlightRanges
                    ? window._macwikiHighlightRanges[payload.id]
                    : null;
                const range = stored && stored.range ? stored.range : null;
                const mark = document.querySelector(
                    '[data-highlight-id="' + payload.id + '"]'
                );
                const startNode = range
                    ? (range.startContainer.nodeType === Node.TEXT_NODE
                        ? range.startContainer.parentElement
                        : range.startContainer)
                    : mark;
                const owner = startNode && startNode.closest
                    ? startNode.closest('[data-occurrence]')
                    : null;
                const duplicateCount = Array.from(
                    document.querySelectorAll('[data-occurrence]')
                ).filter(function (element) {
                    return element.textContent.includes(payload.text);
                }).length;

                return JSON.stringify({
                    success: success === true,
                    ownerID: owner ? owner.id : null,
                    text: range ? range.toString() : (mark ? mark.textContent : null),
                    duplicateCount: duplicateCount
                });
            })();
            """
        )
        let resultData = try #require(resultJSON.data(using: .utf8))
        return try JSONDecoder().decode(RetryObservation.self, from: resultData)
    }

    private struct RetryObservation: Decodable {
        let success: Bool
        let ownerID: String?
        let text: String?
        let duplicateCount: Int
    }

    private static let duplicatePassage = "a passage repeated word for word"
    private static let firstContextBefore = "The first record contains "
    private static let firstContextAfter = " before its first ending."
    private static let secondContextBefore = "The second record contains "
    private static let secondContextAfter = " before its second ending."

    private static let duplicatePassageFixture = """
    <!doctype html>
    <html>
      <head><meta charset="utf-8"></head>
      <body>
        <section>
          <p id="first-occurrence" data-occurrence>\(firstContextBefore)\(duplicatePassage)\(firstContextAfter)</p>
        </section>
        <section>
          <p id="second-occurrence" data-occurrence>\(secondContextBefore)\(duplicatePassage)\(secondContextAfter)</p>
        </section>
      </body>
    </html>
    """
}
