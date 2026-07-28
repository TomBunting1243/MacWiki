import Testing

@testable import MacWiki

struct ReaderTableOfContentsPlacementTests {
    @Test func inspectorRemainsTheDefaultRevertiblePlacement() {
        #expect(ReaderTableOfContentsPlacement.inspector.rawValue == "Inspector")
        #expect(!ReaderTableOfContentsPlacement.inspector.usesReaderOverlay)
    }

    @Test func bothDocumentEdgesAreExplicitOverlayChoices() {
        #expect(ReaderTableOfContentsPlacement.readerLeading.usesReaderOverlay)
        #expect(ReaderTableOfContentsPlacement.readerTrailing.usesReaderOverlay)
        #expect(ReaderTableOfContentsPlacement.allCases.count == 3)
    }

}
