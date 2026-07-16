import SwiftUI
import Testing
import WebKit

@testable import MacWiki

@MainActor
struct WebViewInspectorProjectionIdentityTests {
    @Test func identityRequiresExactSurfaceDocumentAndGeneration() throws {
        let coordinator = makeCoordinator(title: "Reader Article", revision: 42)
        let webView = WKWebView()
        let otherWebView = WKWebView()
        coordinator.lastLoadedArticleTitle = "Reader Article"
        coordinator.lastLoadedHTMLSignature = 42
        coordinator.attachNewWebView(webView)

        let identity = try #require(coordinator.inspectorProjectionIdentity(for: webView))
        #expect(coordinator.isCurrentInspectorProjection(identity, on: webView))
        #expect(coordinator.inspectorProjectionIdentity(for: otherWebView) == nil)

        coordinator.lastLoadedArticleTitle = "Different Article"
        #expect(coordinator.inspectorProjectionIdentity(for: webView) == nil)
        coordinator.lastLoadedArticleTitle = "Reader Article"

        coordinator.lastLoadedHTMLSignature = 43
        #expect(coordinator.inspectorProjectionIdentity(for: webView) == nil)
        coordinator.lastLoadedHTMLSignature = 42

        coordinator.inspectorProjectionGeneration &+= 1
        #expect(!coordinator.isCurrentInspectorProjection(identity, on: webView))
        #expect(coordinator.inspectorProjectionIdentity(for: webView)?.generation == 1)
    }

    private func makeCoordinator(title: String, revision: UInt64) -> MacWiki.WebView.Coordinator {
        MacWiki.WebView.Coordinator(
            tabID: UUID(),
            onLinkTapped: nil,
            onOpenArticleInNewWindow: nil,
            scrollPosition: .constant(0),
            onScrollProgress: nil,
            fallbackScrollProgress: nil,
            appState: nil,
            modelContext: nil,
            onTextSelected: nil,
            onSelectionCleared: nil,
            highlights: [],
            articleTitle: title,
            contentRevision: revision,
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
}
