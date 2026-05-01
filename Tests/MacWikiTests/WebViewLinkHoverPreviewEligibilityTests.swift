import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct WebViewLinkHoverPreviewEligibilityTests {
    @Test func allowsRegularInternalArticleLinkPreview() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://en.wikipedia.org/wiki/Alan_Turing")!

        #expect(coordinator.shouldPresentHoverPreview(for: url, previewTitle: nil))
    }

    @Test func rejectsCurrentArticlePreview() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://en.wikipedia.org/wiki/Swift_(programming_language)")!

        #expect(!coordinator.shouldPresentHoverPreview(for: url, previewTitle: nil))
    }

    @Test func rejectsFileNamespacePreview() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://en.wikipedia.org/wiki/File:Example.jpg")!

        #expect(!coordinator.shouldPresentHoverPreview(for: url, previewTitle: nil))
    }

    @Test func rejectsImageNamespacePreview() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://en.wikipedia.org/wiki/Image:Example.png")!

        #expect(!coordinator.shouldPresentHoverPreview(for: url, previewTitle: nil))
    }

    @Test func rejectsMediaNamespacePreviewFromResolvedTitle() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://en.wikipedia.org/wiki/Example")!

        #expect(!coordinator.shouldPresentHoverPreview(for: url, previewTitle: "Media:Example.webm"))
    }

    @Test func rejectsDirectMediaFileURL() {
        let coordinator = makeCoordinator(currentArticleTitle: "Swift (programming language)")
        let url = URL(string: "https://upload.wikimedia.org/wikipedia/commons/a/a9/Example.jpg")!

        #expect(!coordinator.shouldPresentHoverPreview(for: url, previewTitle: "Example"))
    }

    private func makeCoordinator(currentArticleTitle: String) -> WebView.Coordinator {
        WebView.Coordinator(
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
            articleTitle: currentArticleTitle,
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
