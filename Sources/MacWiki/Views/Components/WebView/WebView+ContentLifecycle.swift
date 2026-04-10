import AppKit
import Foundation
import WebKit

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
        hasUserDrivenScrollSinceLoad = false
        syncRestoreTelemetryMode(on: webView, force: true)
        self.webView = webView
        openTimer?.wrappedValue.markWebViewDidFinish()
        syncNativeHighlightMenuMode(on: webView, force: true)
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
            guard let self, let webView else { return }
            self.setupScrollObserver(for: webView)

            self.scheduleForCurrentWebView(after: 0.04, webView: webView) { [weak self, weak webView] in
                guard let self, let webView else { return }
                if let scrollView = self.findScrollView(in: webView) {
                    self.reportScrollProgress(from: scrollView, force: true)
                }
                if self.isSectionTrackingRequested {
                    self.publishVisibleSection(from: webView, force: true)
                }
            }

            self.scheduleForCurrentWebView(after: 0.06, webView: webView) { [weak self, weak webView] in
                guard let self, let webView else { return }
                if self.isSectionTrackingRequested {
                    self.publishTableOfContents(from: webView)
                }
                if self.isReferencesRequested {
                    self.publishReferences(from: webView)
                }
            }

            self.scheduleForCurrentWebView(after: 0.24, webView: webView) { [weak self, weak webView] in
                guard let self, let webView else { return }
                if self.isSectionTrackingRequested && !self.inspectorPublisher.hasPublishedNonEmptyTOCSinceLoad {
                    self.publishTableOfContents(from: webView)
                }
                if self.isReferencesRequested && !self.inspectorPublisher.hasPublishedNonEmptyReferencesSinceLoad {
                    self.publishReferences(from: webView)
                }
                if self.isSectionTrackingRequested {
                    self.publishVisibleSection(from: webView, force: true)
                }
            }
        }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webContentTerminationCount += 1
        guard webContentTerminationCount <= 2 else { return }

        isContentLoadInFlight = true
        expectedNavigationToken = nil
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
        isContentLoadInFlight = false
        expectedNavigationToken = nil
        cancelScriptedScrollRestore(on: webView)
        activeRestoreSessionID = nil
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        syncRestoreTelemetryMode(on: webView, force: true)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isContentLoadInFlight = false
        expectedNavigationToken = nil
        cancelScriptedScrollRestore(on: webView)
        activeRestoreSessionID = nil
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        syncRestoreTelemetryMode(on: webView, force: true)
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
        onContentReveal?()
        if !pendingPostRevealTasks.isEmpty {
            let tasks = pendingPostRevealTasks
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            for task in tasks {
                task()
            }
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
        pendingPostRevealTasks.removeAll(keepingCapacity: false)
        inspectorPublisher.resetForContentReload()
    }

    func beginContentReload(on webView: WKWebView, htmlContent: String, baseURL: URL?) {
        isContentLoadInFlight = true
        syncRestoreTelemetryMode(on: webView, force: true)
        let navigation = webView.loadHTMLString(htmlContent, baseURL: baseURL)
        expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
    }
}
