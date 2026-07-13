import Testing

@testable import MacWiki

struct ReaderToolbarLayoutTests {
    @Test func densityTracksNarrowCompactAndRegularWidths() {
        #expect(ReaderToolbarDensity(width: 539) == .narrow)
        #expect(ReaderToolbarDensity(width: 540) == .compact)
        #expect(ReaderToolbarDensity(width: 779) == .compact)
        #expect(ReaderToolbarDensity(width: 780) == .regular)
    }

    @Test func visibilityProgressivelyPromotesOverflowActions() {
        let narrow = ReaderToolbarVisibility(width: 500)
        #expect(!narrow.showsBackForward)
        #expect(!narrow.showsReaderStyle)
        #expect(!narrow.showsShare)
        #expect(!narrow.showsPageViews)
        #expect(!narrow.showsOpenInBrowser)
        #expect(narrow.hasOverflowActions)

        let wide = ReaderToolbarVisibility(width: 940)
        #expect(wide.showsBackForward)
        #expect(wide.showsReaderStyle)
        #expect(wide.showsShare)
        #expect(wide.showsPageViews)
        #expect(wide.showsOpenInBrowser)
        #expect(!wide.hasOverflowActions)
    }
}
