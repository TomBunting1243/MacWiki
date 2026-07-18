import Testing

@testable import MacWiki

struct HighlightNoteTextTests {
    @Test func stripsWikipediaCitationMarkersFromNotesPresentation() {
        #expect(
            HighlightNoteText.displayText(
                for: "Ada described the engine.[1][2] Her notes followed [3–5] in 1843.[a]"
            ) == "Ada described the engine. Her notes followed in 1843."
        )
    }

    @Test func preservesEditorialBracketsAndUserFacingProse() {
        #expect(
            HighlightNoteText.displayText(
                for: "The claim was [citation needed], while the transcript reads [sic]."
            ) == "The claim was [citation needed], while the transcript reads [sic]."
        )
    }

    @Test func stripsOnlyPresentationWhileRehydrateKeepsExactAnchorText() {
        let sourceText = "A passage with its source.[17]"
        let highlight = Highlight(
            text: sourceText,
            articleTitle: "Notes",
            startOffset: 4,
            length: sourceText.count,
            contextBefore: "Before ",
            contextAfter: " after."
        )

        let request = AppState.HighlightRehydrateRequest(highlight: highlight)

        #expect(HighlightNoteText.displayText(for: highlight.text) == "A passage with its source.")
        #expect(request.text == sourceText)
        #expect(request.contextBefore == "Before ")
        #expect(request.contextAfter == " after.")
    }
}
