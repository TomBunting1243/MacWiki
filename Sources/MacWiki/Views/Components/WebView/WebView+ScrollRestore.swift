import AppKit
import Foundation
import WebKit

extension WebView.Coordinator {
    func handleScrollRestoreReady(_ data: [String: Any]) {
        guard let sessionIDString = data["sessionID"] as? String,
              let sessionID = UUID(uuidString: sessionIDString),
              isRestoreSessionActive(sessionID),
              let webView,
              webView.alphaValue < 1 else {
            return
        }

        if let y = data["y"] as? Double {
            lastKnownScrollY = CGFloat(y)
        }

        revealWebView(webView, animated: true)
    }

    func scheduleRevealAfterRestore(
        for webView: WKWebView,
        desiredY: CGFloat,
        fallbackProgress: Double,
        restoreSessionID: UUID
    ) {
        let checkpoints = WebViewScrollRestoreController.revealCheckpoints(preferImmediateReveal: preferImmediateReveal)
        for (index, delay) in checkpoints.enumerated() {
            scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                guard webView.alphaValue < 1 else { return }

                let probeScript = """
                (function() {
                    var y = window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
                    var docHeight = Math.max(
                        document.documentElement ? document.documentElement.scrollHeight : 0,
                        document.body ? document.body.scrollHeight : 0
                    );
                    var maxScroll = Math.max(docHeight - window.innerHeight, 0);
                    var progress = maxScroll > 0 ? Math.min(Math.max(y / maxScroll, 0), 1) : 1;
                    return { y: y, progress: progress, maxScroll: maxScroll };
                })();
                """
                webView.evaluateJavaScript(probeScript) { [weak self, weak webView] result, _ in
                    guard let self, let webView else { return }
                    guard self.isRestoreSessionActive(restoreSessionID) else { return }
                    let isFinalProbe = index == checkpoints.count - 1
                    if self.shouldRevealAfterRestoreProbe(
                        probeResult: result,
                        desiredY: desiredY,
                        fallbackProgress: fallbackProgress,
                        isFinalProbe: isFinalProbe
                    ) {
                        self.revealWebView(webView)
                    }
                }
            }
        }
    }

    func shouldRevealAfterRestoreProbe(
        probeResult: Any?,
        desiredY: CGFloat,
        fallbackProgress: Double,
        isFinalProbe: Bool
    ) -> Bool {
        WebViewScrollRestoreController.shouldRevealAfterRestoreProbe(
            probeResult: probeResult,
            desiredY: desiredY,
            fallbackProgress: fallbackProgress,
            isFinalProbe: isFinalProbe,
            preferImmediateReveal: preferImmediateReveal
        )
    }

    func beginRestoreSession() -> UUID {
        let sessionID = UUID()
        activeRestoreSessionID = sessionID
        return sessionID
    }

    func isRestoreSessionActive(_ sessionID: UUID) -> Bool {
        activeRestoreSessionID == sessionID
    }

    func scheduleForRestoreSession(
        _ sessionID: UUID,
        after delay: TimeInterval,
        _ work: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isRestoreSessionActive(sessionID) else { return }
            work()
        }
    }

    func scheduleForCurrentWebView(
        after delay: TimeInterval,
        webView expectedWebView: WKWebView,
        _ work: @escaping () -> Void
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak expectedWebView] in
            guard let self, let expectedWebView else { return }
            guard self.webView === expectedWebView else { return }
            work()
        }
    }

    var scriptedRestoreRetryDelays: [TimeInterval] {
        WebViewScrollRestoreController.retryDelays(preferImmediateReveal: preferImmediateReveal)
    }

    var scriptedRestoreRevealCheckpoints: [TimeInterval] {
        WebViewScrollRestoreController.revealCheckpoints(preferImmediateReveal: preferImmediateReveal)
    }

    func cancelScriptedScrollRestore(on webView: WKWebView?) {
        guard let webView else { return }
        let script = "window.cancelMacWikiScrollRestore && window.cancelMacWikiScrollRestore();"
        webView.evaluateJavaScript(script)
    }

    func startScriptedScrollRestore(
        on webView: WKWebView,
        desiredY: CGFloat,
        fallbackProgress: Double,
        restoreSessionID: UUID
    ) {
        let retryDelays = scriptedRestoreRetryDelays
        let revealCheckpoints = scriptedRestoreRevealCheckpoints
        let retryDelaysMs = retryDelays.map { Int(($0 * 1000).rounded()) }
        let revealCheckpointsMs = revealCheckpoints.map { Int(($0 * 1000).rounded()) }
        let clampedFallback = min(max(fallbackProgress, 0), 1)
        let maxBridgeDelay = max(
            retryDelays.last ?? 0,
            revealCheckpoints.last ?? 0
        )
        let programmaticWindow = maxBridgeDelay + 0.55

        let payload: [String: Any] = [
            "sessionID": restoreSessionID.uuidString,
            "desiredY": Double(desiredY),
            "fallbackProgress": clampedFallback,
            "preferImmediateReveal": preferImmediateReveal,
            "retryDelaysMs": retryDelaysMs,
            "revealCheckpointsMs": revealCheckpointsMs
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let jsonString = String(data: data, encoding: .utf8) else {
            startFallbackNativeScrollRestore(
                on: webView,
                desiredY: desiredY,
                fallbackProgress: clampedFallback,
                restoreSessionID: restoreSessionID,
                retryDelays: retryDelays
            )
            scheduleRevealAfterRestore(
                for: webView,
                desiredY: desiredY,
                fallbackProgress: clampedFallback,
                restoreSessionID: restoreSessionID
            )
            return
        }

        if desiredY > 0 {
            markProgrammaticScroll(y: desiredY, activeFor: programmaticWindow)
        } else {
            markProgrammaticScroll(activeFor: programmaticWindow)
        }

        let script = "window.beginMacWikiScrollRestore && window.beginMacWikiScrollRestore(\(jsonString));"
        webView.evaluateJavaScript(script) { [weak self, weak webView] result, error in
            guard let self, let webView else { return }
            guard self.isRestoreSessionActive(restoreSessionID) else { return }

            let didStartScriptedRestore = (result as? Bool) == true && error == nil
            if !didStartScriptedRestore {
                self.startFallbackNativeScrollRestore(
                    on: webView,
                    desiredY: desiredY,
                    fallbackProgress: clampedFallback,
                    restoreSessionID: restoreSessionID,
                    retryDelays: retryDelays
                )
                self.scheduleRevealAfterRestore(
                    for: webView,
                    desiredY: desiredY,
                    fallbackProgress: clampedFallback,
                    restoreSessionID: restoreSessionID
                )
                return
            }

            let failsafeDelay = maxBridgeDelay + (self.preferImmediateReveal ? 0.14 : 0.32)
            self.scheduleForRestoreSession(restoreSessionID, after: failsafeDelay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.revealWebView(webView, animated: true)
            }
        }
    }

    func startFallbackNativeScrollRestore(
        on webView: WKWebView,
        desiredY: CGFloat,
        fallbackProgress: Double,
        restoreSessionID: UUID,
        retryDelays: [TimeInterval]
    ) {
        if desiredY > 0 {
            markProgrammaticScroll(y: desiredY)
            webView.evaluateJavaScript("window.scrollTo(0, \(desiredY))")

            for delay in retryDelays {
                scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.markProgrammaticScroll(y: desiredY)
                    webView.evaluateJavaScript("window.scrollTo(0, \(desiredY))")
                }
            }
            return
        }

        guard fallbackProgress > 0.01 else { return }
        let restoreScript = """
        (function() {
            var maxScroll = Math.max(
                document.documentElement.scrollHeight,
                document.body ? document.body.scrollHeight : 0
            ) - window.innerHeight;
            if (maxScroll > 0) {
                window.scrollTo(0, maxScroll * \(fallbackProgress));
            }
        })();
        """

        markProgrammaticScroll()
        webView.evaluateJavaScript(restoreScript)

        for delay in retryDelays {
            scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.markProgrammaticScroll()
                webView.evaluateJavaScript(restoreScript)
            }
        }
    }

    func markProgrammaticScroll(
        y: CGFloat? = nil,
        activeFor duration: TimeInterval = 0.22
    ) {
        let now = Date().timeIntervalSinceReferenceDate
        lastProgrammaticScrollTimestamp = now
        programmaticScrollActiveUntil = max(programmaticScrollActiveUntil, now + max(duration, 0.08))
        if let y {
            lastKnownScrollY = y
        }
    }

    func isProgrammaticScrollActive(now: TimeInterval) -> Bool {
        if hasProgrammaticScrollInFlight {
            return true
        }
        if now < programmaticScrollActiveUntil {
            return true
        }
        return (now - lastProgrammaticScrollTimestamp) < 0.16
    }

    func noteUserDrivenScroll(now: TimeInterval) {
        let wasProgrammatic = (now - lastProgrammaticScrollTimestamp) < 0.26
        guard !wasProgrammatic else { return }
        hasUserDrivenScrollSinceLoad = true
        hasProgrammaticScrollInFlight = false
        programmaticScrollActiveUntil = now

        if activeRestoreSessionID != nil {
            cancelScriptedScrollRestore(on: webView)
            activeRestoreSessionID = nil
            clearInitialRestoreTelemetryGuard()
            if let webView, webView.alphaValue < 1 {
                revealWebView(webView, animated: false)
            }
        }
    }

    func restoreScrollPositionIfNeeded(on webView: WKWebView, desiredY: CGFloat) {
        let now = Date().timeIntervalSinceReferenceDate
        if isContentLoadInFlight {
            return
        }
        if hasUserDrivenScrollSinceLoad || activeRestoreSessionID != nil {
            return
        }
        if (now - lastJSTelemetryTimestamp) < 0.35 {
            return
        }
        if isProgrammaticScrollActive(now: now) {
            return
        }

        let delta = abs(lastKnownScrollY - desiredY)
        guard delta > 6 else { return }

        let script = "window.scrollTo(0, \(desiredY));"
        markProgrammaticScroll(y: desiredY)
        webView.evaluateJavaScript(script)
    }
}
