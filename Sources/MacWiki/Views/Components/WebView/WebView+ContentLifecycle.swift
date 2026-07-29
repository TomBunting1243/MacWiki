import AppKit
import Foundation
import WebKit

enum WebViewContentFailurePolicy {
    static func shouldReport(_ error: Error) -> Bool {
        let nsError = error as NSError
        return !(nsError.domain == NSURLErrorDomain && nsError.code == URLError.cancelled.rawValue)
    }
}

extension WebView.Coordinator {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let expectedNavigationToken,
           let navigation,
           ObjectIdentifier(navigation) != expectedNavigationToken {
            return
        }
        isContentLoadInFlight = false
        expectedNavigationToken = nil
        webContentTerminationCount = 0
        contentLoadFailed = false
        hasUserDrivenScrollSinceLoad = false
        syncRestoreTelemetryMode(on: webView, force: true)
        self.webView = webView
        openTimer?.wrappedValue.markWebViewDidFinish()
        syncLinkPreviewImmediateModifier(on: webView, force: true)
        syncNativeHighlightMenuMode(on: webView, force: true)
        syncReaderAccessibilityStyle(on: webView, force: true)
        let restoreSessionID = beginRestoreSession()
        let scrollY = scrollPosition.wrappedValue
        let fallbackProgress = self.fallbackScrollProgress ?? 0
        let hasRestoreTarget = scrollY > 6 || fallbackProgress > 0.01
        let shouldDeferRevealUntilRestored = hasRestoreTarget

        applyReaderAppearance(to: webView, force: true) { [weak self, weak webView] _ in
            guard let self, let webView else { return }
            guard self.isRestoreSessionActive(restoreSessionID) else { return }
            if !shouldDeferRevealUntilRestored {
                self.revealWebView(webView, animated: true)
            }
        }

        let restoreGuardNow = Date().timeIntervalSinceReferenceDate
        configureInitialRestoreTelemetryGuard(
            scrollY: scrollY,
            fallbackProgress: fallbackProgress,
            now: restoreGuardNow
        )
        syncScrollTelemetryMode(on: webView, force: true)

        if !highlights.isEmpty {
            let highlightDelay: TimeInterval = preferImmediateReveal ? 0.03 : 0.12
            scheduleForRestoreSession(restoreSessionID, after: highlightDelay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.applyHighlights(to: webView)
                self.openTimer?.wrappedValue.markHighlightsApplied()
            }
        }

        if shouldDeferRevealUntilRestored {
            startScriptedScrollRestore(
                on: webView,
                desiredY: scrollY,
                fallbackProgress: fallbackProgress,
                restoreSessionID: restoreSessionID
            )
        } else {
            let failsafeDelay: TimeInterval = preferImmediateReveal ? 0.16 : 0.35
            scheduleForRestoreSession(restoreSessionID, after: failsafeDelay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.revealWebView(webView, animated: true)
            }
        }

        runAfterReveal { [weak self, weak webView] in
            guard let self, let webView,
                  let projectionIdentity = self.inspectorProjectionIdentity(for: webView) else { return }

            for step in WebViewInspectorProjectionSchedulePolicy.steps {
                self.scheduleForCurrentWebView(after: step.delay, webView: webView) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    let projection = WebViewInspectorProjectionSchedulePolicy.ProjectionState(
                        hasTableOfContentsResult: self.inspectorProjection.hasTableOfContentsResult,
                        hasReferencesResult: self.inspectorProjection.hasReferencesResult
                    )
                    let requests = WebViewInspectorProjectionSchedulePolicy.requests(
                        for: step,
                        projection: projection,
                        isCurrentProjection: self.isCurrentInspectorProjection(
                            projectionIdentity,
                            on: webView
                        )
                    )

                    for request in requests {
                        switch request {
                        case .tableOfContents:
                            self.publishTableOfContents(from: webView)
                        case .references:
                            self.publishReferences(from: webView)
                        }
                    }
                }
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentRevealPublisher.cancel()
        hasReportedContentReveal = false
        webContentTerminationCount += 1
        guard webContentTerminationCount <= 2 else {
            let error = NSError(
                domain: WKError.errorDomain,
                code: WKError.webContentProcessTerminated.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "The article renderer stopped repeatedly."]
            )
            finishContentLoadFailure(on: webView, error: error, shouldReport: true)
            return
        }

        isContentLoadInFlight = true
        expectedNavigationToken = nil
        beginInspectorProjectionReplacement()
        cancelScriptedScrollRestore(on: webView)
        activeRestoreSessionID = nil
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        syncRestoreTelemetryMode(on: webView, force: true)
        if let recoveryHTMLPayload {
            let navigation = webView.loadHTMLString(
                recoveryHTMLPayload,
                baseURL: recoveryBaseURL ?? URL(string: "https://en.wikipedia.org/wiki/")
            )
            expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
        } else {
            let navigation = webView.reload()
            expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard isExpectedNavigation(navigation) else { return }
        finishContentLoadFailure(
            on: webView,
            error: error,
            shouldReport: WebViewContentFailurePolicy.shouldReport(error)
        )
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard isExpectedNavigation(navigation) else { return }
        finishContentLoadFailure(
            on: webView,
            error: error,
            shouldReport: WebViewContentFailurePolicy.shouldReport(error)
        )
    }

    private func isExpectedNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let expectedNavigationToken, let navigation else { return true }
        return ObjectIdentifier(navigation) == expectedNavigationToken
    }

    private func finishContentLoadFailure(on webView: WKWebView, error: Error, shouldReport: Bool) {
        contentRevealPublisher.cancel()
        isContentLoadInFlight = false
        expectedNavigationToken = nil
        cancelScriptedScrollRestore(on: webView)
        activeRestoreSessionID = nil
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        syncRestoreTelemetryMode(on: webView, force: true)
        guard shouldReport else { return }

        contentLoadFailed = true
        DispatchQueue.main.async { [weak self] in
            self?.onContentLoadFailure?(error)
        }
    }

    func applyReaderAppearance(to webView: WKWebView, force: Bool = false, completion: ((Bool) -> Void)? = nil) {
        let topInsetChanged = abs(lastAppliedReaderTopInset - readerTopInset) > 0.5
        guard force || lastAppliedReaderAppearance != readerAppearance || topInsetChanged else {
            completion?(true)
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: readerAppearance.webPayload),
              let jsonString = String(data: data, encoding: .utf8) else {
            completion?(false)
            return
        }

        let script = """
        window.setReaderAppearance(\(jsonString));
        document.documentElement.style.setProperty('--reader-top-inset', '\(Int(readerTopInset.rounded()))px');
        """
        webView.evaluateJavaScript(script) { [weak self] _, error in
            if error != nil {
                completion?(false)
                return
            }
            self?.lastAppliedReaderAppearance = self?.readerAppearance
            self?.lastAppliedReaderTopInset = self?.readerTopInset ?? -1
            completion?(true)
        }
    }

    func syncReaderAccessibilityStyle(on webView: WKWebView, force: Bool = false) {
        let needsUpdate =
            lastAppliedReduceTransparency != reduceTransparency ||
            lastAppliedDifferentiateWithoutColor != differentiateWithoutColor
        guard force || needsUpdate else { return }
        guard canRunDocumentJavaScript(on: webView) else { return }

        let requestedReduceTransparency = reduceTransparency
        let requestedDifferentiateWithoutColor = differentiateWithoutColor
        webView.evaluateJavaScript(
            ReaderDocumentAccessibilityStyle.updateScript(
                reduceTransparency: requestedReduceTransparency,
                differentiateWithoutColor: requestedDifferentiateWithoutColor
            )
        ) { [weak self] _, error in
            guard error == nil,
                  let self,
                  self.reduceTransparency == requestedReduceTransparency,
                  self.differentiateWithoutColor == requestedDifferentiateWithoutColor else {
                return
            }
            self.lastAppliedReduceTransparency = requestedReduceTransparency
            self.lastAppliedDifferentiateWithoutColor = requestedDifferentiateWithoutColor
        }
    }

    func syncLinkPreviewImmediateModifier(on webView: WKWebView, force: Bool = false) {
        guard force || lastAppliedLinkPreviewImmediateModifier != linkPreviewImmediateModifier else { return }
        lastAppliedLinkPreviewImmediateModifier = linkPreviewImmediateModifier
        let modifierLiteral = WebView.javaScriptStringLiteral(linkPreviewImmediateModifier.javaScriptValue)
        let script = """
        window._macwikiLinkPreviewImmediateModifier = \(modifierLiteral);
        if (window.setLinkPreviewImmediateModifier) {
            window.setLinkPreviewImmediateModifier(\(modifierLiteral));
        }
        """
        webView.evaluateJavaScript(script)
    }

    func syncNativeHighlightMenuMode(on webView: WKWebView, force: Bool = false) {
        guard force || lastAppliedNativeHighlightingMenuEnabled != nativeHighlightingMenuEnabled else { return }
        lastAppliedNativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        let enabledLiteral = nativeHighlightingMenuEnabled ? "true" : "false"
        let script = """
        window._macwikiNativeHighlightingMenuEnabled = \(enabledLiteral);
        if (window.setNativeHighlightingMenuEnabled) {
            window.setNativeHighlightingMenuEnabled(\(enabledLiteral));
        }
        """
        webView.evaluateJavaScript(script)
    }

    func revealWebView(_ webView: WKWebView, animated: Bool? = nil) {
        guard webView.alphaValue < 1 else {
            notifyContentRevealIfNeeded()
            return
        }
        let shouldAnimate = animated ?? true
        guard shouldAnimate else {
            webView.alphaValue = 1
            notifyContentRevealIfNeeded()
            return
        }
        notifyContentRevealIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferImmediateReveal ? 0.12 : 0.18
            webView.animator().alphaValue = 1
        }
    }

    func notifyContentRevealIfNeeded() {
        guard !hasReportedContentReveal else { return }
        hasReportedContentReveal = true
        // WebKit navigation callbacks arrive outside SwiftUI's representable update.
        // Publish immediately so a new document does not pay an unnecessary run-loop hop.
        publishContentReveal(deferred: false)
        drainPendingPostRevealTasks()
    }

    /// Publishes Reader reveal state without re-entering a SwiftUI view update.
    ///
    /// Reused WebViews attach from `makeNSView`, so that path requests a deferred publication.
    /// The scheduler coalesces repeated requests and re-reads the current callback when it fires,
    /// avoiding a callback captured from a superseded representable value.
    func publishContentReveal(deferred: Bool) {
        guard deferred else {
            onContentReveal?()
            return
        }

        contentRevealPublisher.schedule { [weak self] in
            guard let self else { return }
            self.onContentReveal?()
            self.drainPendingPostRevealTasks()
        }
    }

    func drainPendingPostRevealTasks() {
        guard !pendingPostRevealTasks.isEmpty else { return }
        let tasks = pendingPostRevealTasks
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        for task in tasks {
            task()
        }
    }

    func runAfterReveal(_ work: @escaping () -> Void) {
        if hasReportedContentReveal {
            work()
        } else {
            pendingPostRevealTasks.append(work)
        }
    }

    func prepareForContentReload() {
        dismissLinkHoverPreview(immediate: true)
        cancelScriptedScrollRestore(on: webView)
        lastReportedProgress = -1
        lastProgressTimestamp = 0
        hasUserDrivenScrollSinceLoad = false
        clearInitialRestoreTelemetryGuard()
        isContentLoadInFlight = true
        expectedNavigationToken = nil
        activeRestoreSessionID = nil
        hasProgrammaticScrollInFlight = false
        programmaticScrollActiveUntil = 0
        highVelocityUserScrollUntil = 0
        hasReportedContentReveal = false
        contentLoadFailed = false
        contentRevealPublisher.cancel()
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        beginInspectorProjectionReplacement()
    }

    private func beginInspectorProjectionReplacement() {
        inspectorProjectionGeneration &+= 1
        inspectorPublisher.resetForContentReload()
        inspectorProjection = .empty
        lastAppliedSectionTrackingRequest = nil
    }

    func beginContentReload(on webView: WKWebView, htmlContent: String, baseURL: URL?) {
        isContentLoadInFlight = true
        syncRestoreTelemetryMode(on: webView, force: true)
        let navigation = webView.loadHTMLString(htmlContent, baseURL: baseURL)
        expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
    }
}
