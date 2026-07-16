import SwiftUI
import Testing
import WebKit

@testable import MacWiki

@MainActor
struct WebViewInspectorDemandObservationTests {
    @Test func nativeObservationSequencePublishesTheCurrentInspectorDemand() async {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.inspectorVisible = true
        appState.inspectorMode = .info
        let coordinator = makeCoordinator(appState: appState)
        let webView = WKWebView(frame: .zero)

        coordinator.attachNewWebView(webView)
        await drainObservationTurn()

        #expect(coordinator.webView === webView)
        #expect(coordinator.isSectionTrackingRequested)
        #expect(!coordinator.isReferencesRequested)

        appState.inspectorMode = .references
        await drainObservationTurn()

        #expect(!coordinator.isSectionTrackingRequested)
        #expect(coordinator.isReferencesRequested)
        coordinator.cleanup()
    }

    @Test func replacingAndCleaningUpAppStateCancelsStaleDemand() async {
        let originalState = AppState(persistenceMode: .ephemeral)
        originalState.inspectorVisible = true
        originalState.inspectorMode = .info
        let replacementState = AppState(persistenceMode: .ephemeral)
        replacementState.inspectorVisible = true
        replacementState.inspectorMode = .notes
        let coordinator = makeCoordinator(appState: originalState)
        let webView = WKWebView(frame: .zero)

        coordinator.attachNewWebView(webView)
        await drainObservationTurn()
        coordinator.updateAppState(replacementState)
        await drainObservationTurn()

        #expect(!coordinator.isSectionTrackingRequested)
        #expect(!coordinator.isReferencesRequested)

        originalState.inspectorMode = .references
        await drainObservationTurn()

        #expect(!coordinator.isSectionTrackingRequested)
        #expect(!coordinator.isReferencesRequested)

        replacementState.inspectorMode = .info
        await drainObservationTurn()
        #expect(coordinator.isSectionTrackingRequested)

        coordinator.cleanup()
        replacementState.inspectorMode = .references
        await drainObservationTurn()

        #expect(coordinator.appState == nil)
        #expect(coordinator.webView == nil)
        #expect(coordinator.isSectionTrackingRequested)
        #expect(!coordinator.isReferencesRequested)
    }

    private func drainObservationTurn() async {
        for _ in 0..<4 {
            await Task.yield()
        }
    }

    private func makeCoordinator(appState: AppState) -> MacWiki.WebView.Coordinator {
        MacWiki.WebView.Coordinator(
            tabID: UUID(),
            onLinkTapped: nil,
            onOpenArticleInNewWindow: nil,
            scrollPosition: .constant(0),
            onScrollProgress: nil,
            fallbackScrollProgress: nil,
            appState: appState,
            modelContext: nil,
            onTextSelected: nil,
            onSelectionCleared: nil,
            highlights: [],
            articleTitle: "Ada Lovelace",
            readerAppearance: .default,
            readerTopInset: 56,
            preferImmediateReveal: false,
            onTableOfContentsUpdate: nil,
            onReferencesUpdate: nil,
            onVisibleSectionChange: nil,
            onContentReveal: nil,
            onLinkHoverPreviewChange: nil,
            linkPreviewImmediateModifier: .command,
            nativeHighlightingMenuEnabled: false
        )
    }
}
