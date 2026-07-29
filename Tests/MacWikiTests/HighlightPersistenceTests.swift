import Foundation
import SwiftData
import SwiftUI
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

    @Test func successfulColorUpdatePersistsTheColorAndTimestamp() throws {
        let context = try makeInMemoryContext()
        let highlight = fixtureHighlight()
        let originalUpdatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        highlight.updatedAt = originalUpdatedAt
        context.insert(highlight)
        try context.save()

        let updated = HighlightPersistence.updateColor(
            of: highlight,
            to: .blue,
            in: context
        )

        #expect(updated)
        #expect(highlight.color == .blue)
        #expect(highlight.updatedAt > originalUpdatedAt)
        #expect(!context.hasChanges)
    }

    @Test func failedColorUpdateRollsBackAndReportsTheAttempt() throws {
        let fixture = try makeReadOnlyHighlightContext(
            storeName: "HighlightPersistenceColorFailure"
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
            PersistenceIssueCenter.shared.dismiss()
        }
        PersistenceIssueCenter.shared.dismiss()

        let highlight = try fetchHighlight(id: fixture.highlightID, in: fixture.context)
        let originalUpdatedAt = highlight.updatedAt

        let updated = HighlightPersistence.updateColor(
            of: highlight,
            to: .pink,
            in: fixture.context
        )

        #expect(!updated)
        #expect(highlight.color == .yellow)
        #expect(highlight.updatedAt == originalUpdatedAt)
        #expect(!fixture.context.hasChanges)
        #expect(PersistenceIssueCenter.shared.activeIssue?.operation == "change the highlight color")
    }

    @Test func webViewCoordinatorPublishesColorProjectionAfterSuccessfulPersistence() throws {
        let context = try makeInMemoryContext()
        let highlight = fixtureHighlight()
        context.insert(highlight)
        try context.save()
        let appState = AppState(persistenceMode: .ephemeral)
        let coordinator = makeCoordinator(
            highlight: highlight,
            modelContext: context,
            appState: appState
        )

        let updated = coordinator.updateHighlightColor(
            highlightID: highlight.id,
            color: .orange
        )

        #expect(updated)
        #expect(highlight.color == .orange)
        #expect(appState.pendingHighlightColorChange == AppState.HighlightColorChangeRequest(
            id: highlight.id,
            cssColor: HighlightColor.orange.cssColor
        ))
    }

    @Test func webViewCoordinatorSuppressesColorProjectionWhenPersistenceFails() throws {
        let fixture = try makeReadOnlyHighlightContext(
            storeName: "HighlightPersistenceCoordinatorFailure"
        )
        defer {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
            PersistenceIssueCenter.shared.dismiss()
        }
        PersistenceIssueCenter.shared.dismiss()

        let highlight = try fetchHighlight(id: fixture.highlightID, in: fixture.context)
        let appState = AppState(persistenceMode: .ephemeral)
        let coordinator = makeCoordinator(
            highlight: highlight,
            modelContext: fixture.context,
            appState: appState
        )

        let updated = coordinator.updateHighlightColor(
            highlightID: highlight.id,
            color: .orange
        )

        #expect(!updated)
        #expect(highlight.color == .yellow)
        #expect(appState.pendingHighlightColorChange == nil)
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

    private func fixtureHighlight() -> Highlight {
        Highlight(
            text: fixtureSelection.text,
            articleTitle: "Ada Lovelace",
            elementPath: fixtureSelection.elementPath,
            startOffset: fixtureSelection.startOffset,
            length: fixtureSelection.length,
            contextBefore: fixtureSelection.contextBefore,
            contextAfter: fixtureSelection.contextAfter,
            sectionTitle: fixtureSelection.sectionTitle
        )
    }

    private func makeReadOnlyHighlightContext(
        storeName: String
    ) throws -> (
        context: ModelContext,
        directoryURL: URL,
        highlightID: UUID
    ) {
        let highlightID = UUID()
        let fixture = try makeReadOnlyLibraryContext(storeName: storeName) { context in
            let highlight = fixtureHighlight()
            highlight.id = highlightID
            highlight.updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
            context.insert(highlight)
        }
        return (fixture.context, fixture.directoryURL, highlightID)
    }

    private func fetchHighlight(id: UUID, in context: ModelContext) throws -> Highlight {
        let targetID = id
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.id == targetID }
        )
        return try #require(context.fetch(descriptor).first)
    }

    private func makeCoordinator(
        highlight: Highlight,
        modelContext: ModelContext,
        appState: AppState
    ) -> WebView.Coordinator {
        WebView.Coordinator(
            tabID: UUID(),
            onLinkTapped: nil,
            onOpenArticleInNewWindow: nil,
            scrollPosition: .constant(0),
            onScrollProgress: nil,
            fallbackScrollProgress: nil,
            appState: appState,
            modelContext: modelContext,
            onTextSelected: nil,
            onSelectionCleared: nil,
            highlights: [highlight],
            articleTitle: highlight.articleTitle,
            contentRevision: 0,
            readerAppearance: .default,
            readerTopInset: 56,
            preferImmediateReveal: false,
            onTableOfContentsUpdate: nil,
            onReferencesUpdate: nil,
            onVisibleSectionChange: nil,
            onContentReveal: nil,
            onLinkHoverPreviewChange: nil,
            linkPreviewImmediateModifier: .default,
            nativeHighlightingMenuEnabled: true
        )
    }

    private func makeReadOnlyContext() throws -> (
        context: ModelContext,
        directoryURL: URL
    ) {
        try makeReadOnlyLibraryContext(storeName: "HighlightPersistenceTests")
    }
}
