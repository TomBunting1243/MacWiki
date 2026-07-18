import Foundation
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

    @Test func inspectorAndReaderConsumeOneRevertiblePlacementSetting() throws {
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let inspector = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let popover = try source("Sources/MacWiki/Views/Components/ReaderStylePopover.swift")
        let settings = try source("Sources/MacWiki/Views/Components/SettingsReadingPane.swift")

        for consumer in [reader, inspector, popover, settings] {
            #expect(consumer.contains("AppStorageKey.Reader.tableOfContentsPlacement"))
        }
        #expect(inspector.contains("if tableOfContentsPlacement == .inspector"))
        #expect(reader.contains("tableOfContentsPlacement.usesReaderOverlay"))
    }

    @Test func overlayUsesNativeGlassWithAccessibleFallbacksAndMotionParity() throws {
        let overlay = try source("Sources/MacWiki/Views/Reader/ReaderTableOfContentsOverlay.swift")

        #expect(overlay.contains(".glassEffect(.regular.interactive()"))
        #expect(overlay.contains("personalization.reduceTransparency"))
        #expect(overlay.contains("personalization.reduceMotion"))
        #expect(overlay.contains("personalization.colorSchemeContrast"))
        #expect(overlay.contains(".accessibilityLabel(\"Show article contents\")"))
        #expect(overlay.contains(".accessibilityLabel(\"Article contents\")"))
        #expect(!overlay.contains("DragGesture"))
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
