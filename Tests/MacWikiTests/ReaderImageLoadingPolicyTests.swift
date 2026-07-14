import Foundation
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

    @Test func initialDocumentHintsOnlyPrioritizeTheFirstThreeImages() throws {
        let source = try source("Sources/MacWiki/Views/Components/WebView.swift")

        #expect(source.contains("private let eagerImageCountForInitialLoad = 3"))
        #expect(source.contains("let desiredLoadingValue = shouldBeEager ? \"eager\" : \"lazy\""))
        #expect(source.contains("let desiredFetchPriority = shouldBeEager ? \"high\" : \"auto\""))
        #expect(source.contains("insertHTMLAttribute(name: \"decoding\", value: \"async\""))
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
