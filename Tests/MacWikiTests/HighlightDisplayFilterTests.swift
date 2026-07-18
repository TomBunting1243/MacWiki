import Foundation
import Testing

@testable import MacWiki

struct HighlightDisplayFilterTests {
    @Test func filtersCitationCssLeakHighlights() {
        let leak = Highlight(
            text: ".mw-parser-output cite.citation{font-style:inherit} Retrieved April 21, 2026",
            articleTitle: "CSS Leak",
            startOffset: 0,
            length: 72,
            sectionTitle: "References"
        )
        let prose = Highlight(
            text: "This is normal article prose that should remain visible.",
            articleTitle: "CSS Leak",
            startOffset: 0,
            length: 54,
            sectionTitle: "History"
        )

        let visible = HighlightDisplayFilter.visibleHighlights(
            from: [leak, prose],
            showStaleHighlights: true,
            showArchivedHighlights: false
        )

        #expect(visible.map(\.text) == [prose.text])
    }

    @Test func filtersLongParserCssReferencePayloads() {
        #expect(HighlightDisplayFilter.isCitationNoise(
            text: #"[1] mw-parser-output .cs1-ws-icon a{background:url("//upload.wikimedia.org/icon.svg")} "Dublin City Council". Archived from the original on 7 January 2019. Retrieved 29 August 2015."#,
            sectionTitle: "References"
        ))
    }

    @Test func filtersBareReferenceNumberHighlights() {
        #expect(HighlightDisplayFilter.isCitationNoise(
            text: "[12]",
            sectionTitle: "History"
        ))
        #expect(HighlightDisplayFilter.isCitationNoise(
            text: "[note 2]",
            sectionTitle: "Notes"
        ))
        #expect(HighlightDisplayFilter.isCitationNoise(
            text: "[1][2][3–5]",
            sectionTitle: "History"
        ))
    }

    @Test func filtersObviousReferenceRowsButKeepsRegularProse() {
        #expect(HighlightDisplayFilter.isCitationNoise(
            text: "[12] Smith, Jane. Example Book. Publisher. Retrieved 2024-06-01.",
            sectionTitle: "References"
        ))

        #expect(!HighlightDisplayFilter.isCitationNoise(
            text: "The article mentions a book title, but this sentence is normal prose.",
            sectionTitle: "History"
        ))
    }

    @Test func preservesStaleAndArchiveVisibilityRules() {
        let current = Highlight(
            text: "Current",
            articleTitle: "State",
            startOffset: 0,
            length: 7
        )
        let stale = Highlight(
            text: "Stale",
            articleTitle: "State",
            startOffset: 8,
            length: 5
        )
        stale.isStale = true
        let archived = Highlight(
            text: "Archived",
            articleTitle: "State",
            startOffset: 14,
            length: 8
        )
        archived.isArchived = true

        let visible = HighlightDisplayFilter.visibleHighlights(
            from: [current, stale, archived],
            showStaleHighlights: false,
            showArchivedHighlights: true
        )

        #expect(visible.map(\.text) == ["Current", "Archived"])
    }
}
