import Foundation
import Testing

@Suite
struct ReaderScrollBehaviorRegressionTests {
    @Test func resizeInvalidatesMetricsWithoutForcingReaderPosition() throws {
        let script = try webViewScript()
        let resizeBehavior = sourceSection(
            script,
            startingAt: "function refreshScrollMetricsAfterResize()",
            endingBefore: "window.addEventListener('load'"
        )

        #expect(resizeBehavior.contains("markMaxScrollDirty(30)"))
        #expect(resizeBehavior.contains("getMaxScroll(true)"))
        #expect(resizeBehavior.contains("schedulePostScroll(true)"))
        #expect(!resizeBehavior.contains("progressBeforeResize"))
        #expect(!resizeBehavior.contains("window.scrollTo"))
        #expect(!script.contains("preserveProgressAcrossResize"))
    }

    @Test func tocUsesOneInterruptibleNativeSmoothScroll() throws {
        let script = try webViewScript()
        let smoothScroll = sourceSection(
            script,
            startingAt: "function smoothScrollToY(targetY, options)",
            endingBefore: "// Expose helpers for TOC/anchor jumps."
        )
        let userIntent = sourceSection(
            script,
            startingAt: "function noteUserScrollIntent()",
            endingBefore: "function isProgrammaticScrollMode"
        )

        #expect(smoothScroll.contains("window.scrollTo({ top: clampedTarget, behavior: 'smooth' })"))
        #expect(smoothScroll.contains("monitorProgrammaticScroll(clampedTarget, durationMs"))
        #expect(!script.contains("runNativeStagedSmoothScroll"))
        #expect(!script.contains("nativeStageTimer"))
        #expect(!script.contains("nativeStageMaxDistance"))
        #expect(userIntent.contains("cancelSmoothScrollAnimation()"))
        #expect(userIntent.contains("programmaticScrollModeUntil = 0"))
        #expect(userIntent.contains("clearTimeout(programmaticScrollForcePostTimer)"))
    }

    @Test func highlightNavigationSharesReducedMotionAwareScrollPath() throws {
        let script = try webViewScript()
        let highlightScroll = sourceSection(
            script,
            startingAt: "window.scrollToHighlight = function (id)",
            endingBefore: "// Restore a single highlight"
        )

        #expect(highlightScroll.contains("window._macwikiSmoothScrollToY(target"))
        #expect(highlightScroll.contains("reason: 'highlight'"))
        #expect(highlightScroll.contains("prefers-reduced-motion: reduce"))
        #expect(highlightScroll.contains("prefersReducedMotion ? 'auto' : 'smooth'"))
    }

    @Test func readerAppearanceInvalidatesHeightAndHeadingCaches() throws {
        let script = try webViewScript()
        let invalidation = sourceSection(
            script,
            startingAt: "window._macwikiInvalidateReaderLayoutMetrics = function ()",
            endingBefore: "})();\n\n// Text Selection Detection"
        )
        let appearance = sourceSection(
            script,
            startingAt: "window.setReaderAppearance = function (options)",
            endingBefore: "// Extract article table of contents"
        )

        #expect(invalidation.contains("markMaxScrollDirty(0)"))
        #expect(invalidation.contains("window._invalidateHeadingCache()"))
        #expect(invalidation.contains("getMaxScroll(true)"))
        #expect(invalidation.contains("schedulePostScroll(true)"))
        #expect(appearance.contains("window._macwikiInvalidateReaderLayoutMetrics()"))
    }

    @Test func readerTelemetryDoesNotTraversePrivateWebKitScrollViews() throws {
        let sources = try [
            "Sources/MacWiki/Views/Components/WebView.swift",
            "Sources/MacWiki/Views/Components/WebView/WebView+ContentLifecycle.swift",
            "Sources/MacWiki/Views/Components/WebView/WebView+ScrollTelemetry.swift"
        ].map(source)
        let combined = sources.joined(separator: "\n")

        #expect(!combined.contains("setupScrollObserver"))
        #expect(!combined.contains("findScrollView"))
        #expect(!combined.contains("enclosingScrollView"))
        #expect(!combined.contains("adaptiveFallback"))
        #expect(!combined.contains("scrollObserver"))
        #expect(combined.contains("handleScrollChanged"))
        #expect(combined.contains("reportScrollProgressValue"))
    }

    private func webViewScript() throws -> String {
        try source("Sources/MacWiki/Resources/WebView.js")
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
    }

    private func sourceSection(
        _ source: String,
        startingAt startMarker: String,
        endingBefore endMarker: String
    ) -> String {
        guard let start = source.range(of: startMarker)?.lowerBound,
              let end = source.range(of: endMarker, range: start..<source.endIndex)?.lowerBound else {
            return ""
        }
        return String(source[start..<end])
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
