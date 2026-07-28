import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct HighlightPersistenceTests {
    @Test func successfulCreationPersistsTheCompleteAnchor() throws {
        let context = try makeInMemoryContext()
        let selection = fixtureSelection

        let created = HighlightPersistence.create(
            from: selection,
            articleTitle: "Ada Lovelace",
            color: .pink,
            note: "First algorithm",
            in: context
        )

        let highlight = try #require(created)
        #expect(highlight.text == selection.text)
        #expect(highlight.elementPath == selection.elementPath)
        #expect(highlight.startOffset == selection.startOffset)
        #expect(highlight.contextBefore == selection.contextBefore)
        #expect(highlight.contextAfter == selection.contextAfter)
        #expect(highlight.sectionTitle == selection.sectionTitle)
        #expect(highlight.color == .pink)
        #expect(highlight.note == "First algorithm")
        #expect(!context.hasChanges)
    }

    @Test func failedCreationRollsBackAndReportsInsteadOfPublishingAHighlight() throws {
        let fixture = try makeReadOnlyContext()
        defer {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
            PersistenceIssueCenter.shared.dismiss()
        }
        PersistenceIssueCenter.shared.dismiss()

        let created = HighlightPersistence.create(
            from: fixtureSelection,
            articleTitle: "Ada Lovelace",
            color: .yellow,
            note: nil,
            in: fixture.context
        )

        #expect(created == nil)
        #expect(!fixture.context.hasChanges)
        #expect(PersistenceIssueCenter.shared.activeIssue?.operation == "create the highlight")
    }

    private var fixtureSelection: TextSelectionData {
        TextSelectionData(
            text: "Analytical Engine",
            elementPath: "main/section[2]/p[1]",
            startOffset: 14,
            length: 17,
            contextBefore: "notes on the ",
            contextAfter: " were published",
            sectionTitle: "Legacy",
            rect: .zero
        )
    }

    private func makeInMemoryContext() throws -> ModelContext {
        try makeInMemoryLibraryContext()
    }

    private func makeReadOnlyContext() throws -> (
        context: ModelContext,
        directoryURL: URL
    ) {
        try makeReadOnlyLibraryContext(storeName: "HighlightPersistenceTests")
    }
}
