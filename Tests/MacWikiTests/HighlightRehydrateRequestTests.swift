import Foundation
import Testing

@testable import MacWiki

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

    @Test func webRestorationPrefersTheDOMAnchorBeforeDocumentFallback() throws {
        let script = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/MacWiki/Resources/WebView.js"),
            encoding: .utf8
        )
        let anchoredSearch = try #require(
            script.range(of: "var range = findTextRangeInAnchoredElement(")
        )
        let documentFallback = try #require(
            script.range(of: "range = findTextRange(text, contextBefore, contextAfter, searchCache, document.body)")
        )

        #expect(anchoredSearch.lowerBound < documentFallback.lowerBound)
        #expect(script.contains("payload.elementPath || ''"))
        #expect(script.contains("Number.isInteger(payload.startOffset)"))
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
