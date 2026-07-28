import Foundation
import Testing
import WebKit

@testable import MacWiki

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

    @Test func tocScrollCompletionIsAwaitedAndIntermediateSectionsStayMuted() throws {
        let script = try webViewScript()
        let tocScroll = sourceSection(
            script,
            startingAt: "window.scrollToSection = function (id)",
            endingBefore: "window.scrollToAnchor"
        )
        let telemetry = sourceSection(
            script,
            startingAt: "function postScroll(force)",
            endingBefore: "window.addEventListener('scroll'"
        )

        #expect(tocScroll.contains("return Promise.resolve(false)"))
        #expect(tocScroll.contains("return new Promise(function (resolve)"))
        #expect(tocScroll.contains("onComplete: resolve"))
        #expect(telemetry.contains("!inProgrammaticMode && sectionTrackingEnabled"))
        #expect(telemetry.contains("!inProgrammaticMode &&\n                    sectionTrackingEnabled"))
        #expect(telemetry.contains("!inProgrammaticMode && sectionTrackingEnabled && window.currentVisibleSectionId"))
    }

    @Test func visibleSectionStartsEmptyBeforeFirstHeadingThreshold() throws {
        let script = try webViewScript()
        let visibleSection = sourceSection(
            script,
            startingAt: "window.currentVisibleSectionId = function ()",
            endingBefore: "// Invalidate cache on layout events"
        )

        #expect(visibleSection.contains("var activeIndex = activeHeadingIndex(scrollTop)"))
        #expect(visibleSection.contains("return activeIndex >= 0 ? _cachedHeadings[activeIndex].id : null"))
        #expect(!visibleSection.contains("_cachedHeadings[0].id"))
        #expect(!visibleSection.contains("upper 60%"))
    }

    @MainActor
    @Test func visibleSectionSelfCorrectsAfterLateDocumentLayoutShift() async throws {
        let script = WebViewResources.scriptSource
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 700))
        webView.loadHTMLString(
            """
            <!doctype html><html><body style="margin:0">
              <div id="late" style="height:0"></div>
              <h2 id="biography">Biography</h2><div style="height:900px"></div>
              <h2 id="death">Death</h2><div style="height:900px"></div>
              <h2 id="work">Work</h2><div style="height:900px"></div>
              <h2 id="legacy">Legacy</h2><div style="height:900px"></div>
            </body></html>
            """,
            baseURL: nil
        )

        for _ in 0..<200 {
            let fixtureLoaded = try? await webView.evaluateJavaScript(
                "document.readyState === 'complete' && document.querySelector('#legacy') !== null"
            )
            if fixtureLoaded as? Bool == true {
                break
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        _ = try await webView.evaluateJavaScript(script)
        _ = try await webView.evaluateJavaScript("window.currentVisibleSectionId()")
        _ = try await webView.evaluateJavaScript("document.querySelector('#late').style.height = '2400px'")
        _ = try await webView.evaluateJavaScript(
            "window.scrollTo(0, document.querySelector('#legacy').offsetTop - 80)"
        )
        let visible = try await webView.evaluateJavaScript("window.currentVisibleSectionId()") as? String

        #expect(visible == "legacy")
    }

    @Test func tocRowOnlyEnqueuesAndNativeBridgeAwaitsSuccessfulSettlement() throws {
        let inspector = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let rowAction = sourceSection(
            inspector,
            startingAt: "return Button {",
            endingBefore: "} label: {"
        )
        let webView = try source("Sources/MacWiki/Views/Components/WebView.swift")
        let nativeRequest = sourceSection(
            webView,
            startingAt: "// Scroll to a specific heading from Table of Contents",
            endingBefore: "// In-page find (Search on Page)."
        )

        #expect(rowAction.contains("pendingTableOfContentsScrollTarget = item.id"))
        #expect(!rowAction.contains("currentVisibleTableOfContentsSectionId"))
        #expect(nativeRequest.contains("try? await webView.callAsyncJavaScript"))
        #expect(nativeRequest.contains("return await window.scrollToSection(sectionID)"))
        #expect(nativeRequest.contains("didReachTarget: result as? Bool == true"))
        #expect(nativeRequest.contains("case .succeeded"))
        #expect(nativeRequest.contains("case .failed"))
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

    @Test func cachedSectionTrackingDoesNotIncreaseBridgeCadence() throws {
        let script = try webViewScript()
        let tuning = sourceSection(
            script,
            startingAt: "function maybeTuneAndReport(now)",
            endingBefore: "function postScroll(force)"
        )
        let modeUpdate = sourceSection(
            script,
            startingAt: "window.setScrollTelemetrySectionTrackingEnabled = function (enabled)",
            endingBefore: "window.setRestoreTelemetryMode"
        )

        #expect(tuning.contains("var baseThrottle = 210"))
        #expect(!tuning.contains("sectionTrackingEnabled ? 150 : 210"))
        #expect(modeUpdate.contains("throttleMs = 210"))
        #expect(script.contains("var lastPostedSectionId = null"))
        #expect(script.contains("sid !== lastPostedSectionId"))
        #expect(script.contains("finalSid !== lastPostedSectionId"))
    }

    @Test func inspectorProjectionNormalizesTOCBeforeVisibleSectionAndRetriesInvalidResults() throws {
        let lifecycle = try source("Sources/MacWiki/Views/Components/WebView/WebView+ContentLifecycle.swift")
        let inspector = try source("Sources/MacWiki/Views/Components/WebView/WebView+Inspector.swift")
        let projectionSchedule = sourceSection(
            lifecycle,
            startingAt: "runAfterReveal {",
            endingBefore: "func webViewWebContentProcessDidTerminate"
        )
        let tocDelay = try #require(projectionSchedule.range(of: "after: 0.06"))
        let referencesDelay = try #require(projectionSchedule.range(of: "after: 0.24"))
        let finalRetry = try #require(projectionSchedule.range(of: "after: 0.90"))

        #expect(tocDelay.lowerBound < referencesDelay.lowerBound)
        #expect(referencesDelay.lowerBound < finalRetry.lowerBound)
        #expect(!projectionSchedule[..<tocDelay.lowerBound].contains("publishVisibleSection"))
        #expect(projectionSchedule.components(separatedBy: "isCurrentInspectorProjection").count - 1 == 5)
        #expect(inspector.contains("guard error == nil,"))
        #expect(inspector.components(separatedBy: "let rows = result as? [[String: Any]]").count - 1 == 2)
        #expect(!inspector.contains("result as? [[String: Any]] ?? []"))
        #expect(inspector.contains("self.publishVisibleSection(from: webView, force: true)"))
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
