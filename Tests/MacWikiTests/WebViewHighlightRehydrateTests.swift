import SwiftData
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct WebViewHighlightRehydrateTests {
    @Test func marksFailedHighlightsStaleFromHighlightResult() throws {
        let modelContext = try makeInMemoryModelContext()
        let restored = Highlight(
            text: "restored text",
            articleTitle: "Rehydration",
            startOffset: 0,
            length: 13
        )
        let failed = Highlight(
            text: "missing text",
            articleTitle: "Rehydration",
            startOffset: 20,
            length: 12
        )
        restored.isStale = true
        failed.isStale = false
        modelContext.insert(restored)
        modelContext.insert(failed)

        let coordinator = makeCoordinator(
            highlights: [restored, failed],
            modelContext: modelContext
        )

        coordinator.handleScriptMessage(
            name: "highlightResult",
            body: [
                "total": 2,
                "success": 1,
                "failedIds": [failed.id.uuidString]
            ]
        )

        #expect(restored.isStale == false)
        #expect(failed.isStale == true)
    }

    @Test func retrySuccessClearsStaleFlagAndPublishesResult() throws {
        let modelContext = try makeInMemoryModelContext()
        let highlight = Highlight(
            text: "found again",
            articleTitle: "Rehydration",
            startOffset: 4,
            length: 11
        )
        highlight.isStale = true
        let originalUpdatedAt = highlight.updatedAt
        modelContext.insert(highlight)

        let appState = AppState(persistenceMode: .ephemeral)
        let pending = AppState.HighlightRehydrateRequest(highlight: highlight)
        appState.pendingHighlightRehydrate = pending
        appState.isHighlightRehydrateInProgress = true

        let coordinator = makeCoordinator(
            highlights: [highlight],
            modelContext: modelContext,
            appState: appState
        )
        let timestamp = originalUpdatedAt.addingTimeInterval(60)

        coordinator.completePendingHighlightRehydrate(
            pending,
            success: true,
            timestamp: timestamp
        )

        #expect(appState.pendingHighlightRehydrate == nil)
        #expect(appState.isHighlightRehydrateInProgress == false)
        #expect(appState.lastHighlightRehydrateResult?.id == highlight.id)
        #expect(appState.lastHighlightRehydrateResult?.success == true)
        #expect(appState.lastHighlightRehydrateResult?.timestamp == timestamp)
        #expect(highlight.isStale == false)
        #expect(highlight.updatedAt == timestamp)
    }

    @Test func retryFailureLeavesHighlightStaleAndPublishesResult() throws {
        let modelContext = try makeInMemoryModelContext()
        let highlight = Highlight(
            text: "still missing",
            articleTitle: "Rehydration",
            startOffset: 4,
            length: 13
        )
        highlight.isStale = true
        let originalUpdatedAt = highlight.updatedAt
        modelContext.insert(highlight)

        let appState = AppState(persistenceMode: .ephemeral)
        let pending = AppState.HighlightRehydrateRequest(highlight: highlight)
        appState.pendingHighlightRehydrate = pending
        appState.isHighlightRehydrateInProgress = true

        let coordinator = makeCoordinator(
            highlights: [highlight],
            modelContext: modelContext,
            appState: appState
        )
        let timestamp = originalUpdatedAt.addingTimeInterval(60)

        coordinator.completePendingHighlightRehydrate(
            pending,
            success: false,
            timestamp: timestamp
        )

        #expect(appState.pendingHighlightRehydrate == nil)
        #expect(appState.isHighlightRehydrateInProgress == false)
        #expect(appState.lastHighlightRehydrateResult?.id == highlight.id)
        #expect(appState.lastHighlightRehydrateResult?.success == false)
        #expect(appState.lastHighlightRehydrateResult?.timestamp == timestamp)
        #expect(highlight.isStale == true)
        #expect(highlight.updatedAt == originalUpdatedAt)
    }

    @Test func retrySaveFailureRollsBackAndPublishesFailure() throws {
        let highlightID = UUID()
        let originalTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = try makeReadOnlyLibraryContext(
            storeName: "WebViewHighlightRehydrateTests"
        ) { context in
            let highlight = Highlight(
                text: "found but not saved",
                articleTitle: "Rehydration",
                startOffset: 4,
                length: 19
            )
            highlight.id = highlightID
            highlight.isStale = true
            highlight.updatedAt = originalTimestamp
            context.insert(highlight)
        }
        defer {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
            PersistenceIssueCenter.shared.dismiss()
        }
        PersistenceIssueCenter.shared.dismiss()

        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.id == highlightID }
        )
        let highlight = try #require(fixture.context.fetch(descriptor).first)
        let appState = AppState(persistenceMode: .ephemeral)
        let pending = AppState.HighlightRehydrateRequest(highlight: highlight)
        appState.pendingHighlightRehydrate = pending
        appState.isHighlightRehydrateInProgress = true
        let coordinator = makeCoordinator(
            highlights: [highlight],
            modelContext: fixture.context,
            appState: appState
        )
        let attemptedTimestamp = originalTimestamp.addingTimeInterval(60)

        coordinator.completePendingHighlightRehydrate(
            pending,
            success: true,
            timestamp: attemptedTimestamp
        )

        #expect(appState.pendingHighlightRehydrate == nil)
        #expect(appState.isHighlightRehydrateInProgress == false)
        #expect(appState.lastHighlightRehydrateResult?.success == false)
        #expect(highlight.isStale)
        #expect(highlight.updatedAt == originalTimestamp)
        #expect(PersistenceIssueCenter.shared.activeIssue?.operation == "restore the highlight")
    }

    private func makeCoordinator(
        highlights: [Highlight],
        modelContext: ModelContext,
        appState: AppState? = nil
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
            highlights: highlights,
            articleTitle: "Rehydration",
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

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Highlight.self,
            Tag.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
