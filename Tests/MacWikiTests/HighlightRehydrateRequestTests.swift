import Testing

@testable import MacWiki

struct HighlightRehydrateRequestTests {
    @Test func buildsRequestFromHighlightAnchorData() {
        let highlight = Highlight(
            text: "important passage",
            articleTitle: "Rehydrate",
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
    }
}
