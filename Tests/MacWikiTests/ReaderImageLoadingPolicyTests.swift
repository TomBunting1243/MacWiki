import Foundation
import SwiftUI
import Testing

@testable import MacWiki

struct ReaderImageLoadingPolicyTests {
    @Test func webKitOwnsLazyImageSchedulingWithoutAPrewarmScheduler() throws {
        let script = try source("Sources/MacWiki/Resources/WebView.js")

        #expect(!script.contains("IntersectionObserver"))
        #expect(!script.localizedCaseInsensitiveContains("prewarm"))
        #expect(!script.contains("setAttribute('loading'"))
        #expect(!script.contains("setAttribute('fetchpriority'"))
        #expect(script.contains("options.maxPrepImages || 240"))
        #expect(script.contains("options.syncFrontload || 3"))
        #expect(script.contains("window.requestIdleCallback(runChunk"))
    }

    @MainActor
    @Test func initialDocumentHintsOnlyPrioritizeTheFirstThreeImages() throws {
        let html = """
        <html><body>
          <img id="first" src="1.jpg">
          <img id="second" src="2.jpg" loading='lazy'>
          <img id="third" src="3.jpg" decoding="sync" fetchpriority="low">
          <img id="fourth" src="4.jpg">
          <img id="fifth" src="5.jpg" loading="eager" decoding="auto" fetchpriority="high">
        </body></html>
        """
        let coordinator = WebView.Coordinator(
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
            articleTitle: "Images",
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
            nativeHighlightingMenuEnabled: false
        )

        let prepared = coordinator.prepareHTMLForInitialLoad(
            html,
            articleTitle: "Images",
            htmlSignature: ReaderDocumentRevision.digest(for: html)
        )
        let first = try imageTag(withID: "first", in: prepared)
        let second = try imageTag(withID: "second", in: prepared)
        let third = try imageTag(withID: "third", in: prepared)
        let fourth = try imageTag(withID: "fourth", in: prepared)
        let fifth = try imageTag(withID: "fifth", in: prepared)

        #expect(first.contains(#"loading="eager""#))
        #expect(first.contains(#"decoding="async""#))
        #expect(first.contains(#"fetchpriority="high""#))
        #expect(second.contains("loading='lazy'"))
        #expect(second.contains(#"decoding="async""#))
        #expect(second.contains(#"fetchpriority="high""#))
        #expect(third.contains(#"loading="eager""#))
        #expect(third.contains(#"decoding="sync""#))
        #expect(third.contains(#"fetchpriority="low""#))
        #expect(fourth.contains(#"loading="lazy""#))
        #expect(fourth.contains(#"decoding="async""#))
        #expect(fourth.contains(#"fetchpriority="auto""#))
        #expect(fifth.contains(#"loading="eager""#))
        #expect(fifth.contains(#"decoding="auto""#))
        #expect(fifth.contains(#"fetchpriority="high""#))
    }

    @Test func unknownDimensionImagesNeverReceiveSyntheticSkeletons() throws {
        let script = try source("Sources/MacWiki/Resources/WebView.js")
        let stylesheet = try source("Sources/MacWiki/Resources/Reader.css")
        let unknownDimensionComment = try #require(
            script.range(of: "Unknown dimensions cannot reserve space")
        )
        let followingSource = script[unknownDimensionComment.lowerBound...]

        #expect(followingSource.contains("return false;"))
        #expect(script.contains("if (!shouldUseImageSkeleton(image)) return;"))
        #expect(!stylesheet.contains("data-macwiki-image-skeleton=\"0\""))
    }

    private func imageTag(withID id: String, in html: String) throws -> String {
        let escapedID = NSRegularExpression.escapedPattern(for: id)
        let regex = try NSRegularExpression(
            pattern: #"<img\b[^>]*\bid\s*=\s*(["'])"# + escapedID + #"\1[^>]*>"#,
            options: [.caseInsensitive]
        )
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        let match = try #require(regex.firstMatch(in: html, range: range))
        let swiftRange = try #require(Range(match.range, in: html))
        return String(html[swiftRange])
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
