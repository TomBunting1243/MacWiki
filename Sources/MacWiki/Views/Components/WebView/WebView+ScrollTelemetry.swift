import AppKit
import Foundation
import WebKit

extension WebView.Coordinator {
    func handleScrollChanged(_ data: [String: Any]) {
        if isContentLoadInFlight {
            return
        }
        let now = Date().timeIntervalSinceReferenceDate
        let userInitiated = data["userInitiated"] as? Bool ?? false
        let isProgrammaticEvent = data["programmatic"] as? Bool ?? false
        let hadProgrammaticInFlight = hasProgrammaticScrollInFlight
        let y = (data["y"] as? Double).map { CGFloat($0) } ?? 0
        let progress = data["progress"] as? Double
        let velocity = max(data["velocity"] as? Double ?? 0, 0)
        let gestureFast = data["gestureFast"] as? Bool ?? false
        let burstHeartbeat = data["burstHeartbeat"] as? Bool ?? false
        let directionChanged = data["directionChanged"] as? Bool ?? false
        lastJSTelemetryTimestamp = now

        if isProgrammaticEvent {
            hasProgrammaticScrollInFlight = true
            markProgrammaticScroll(y: y, activeFor: 0.72)
        } else if hadProgrammaticInFlight {
            hasProgrammaticScrollInFlight = false
            programmaticScrollActiveUntil = max(programmaticScrollActiveUntil, now + 0.16)
        }

        if userInitiated {
            noteUserDrivenScroll(now: now)
            if !isProgrammaticEvent && (velocity > 0.52 || gestureFast || burstHeartbeat) {
                var window: TimeInterval
                if burstHeartbeat {
                    window = 0.66
                } else {
                    window = gestureFast ? 0.46 : 0.34
                }
                if directionChanged {
                    window = min(window, 0.24)
                }
                highVelocityUserScrollUntil = max(highVelocityUserScrollUntil, now + window)
            }
            if directionChanged {
                highVelocityUserScrollUntil = min(
                    max(highVelocityUserScrollUntil, now + 0.12),
                    now + 0.24
                )
            }
        }

        lastKnownScrollY = y
        if shouldIgnoreInitialTopTelemetry(y: y, progress: progress, now: now) {
            return
        }
        if burstHeartbeat {
            return
        }
        let inHighVelocityWindow =
            !isProgrammaticEvent &&
            now < highVelocityUserScrollUntil
        let delta = abs(scrollPosition.wrappedValue - y)
        let dynamicScrollDeltaThreshold =
            inHighVelocityWindow
            ? max(adaptiveScrollDeltaThreshold, directionChanged ? 22 : 40)
            : adaptiveScrollDeltaThreshold
        let dynamicScrollTimeGate =
            inHighVelocityWindow
            ? (
                directionChanged
                ? min(adaptiveScrollTimeGate, 0.72)
                : max(adaptiveScrollTimeGate, 1.25)
            )
            : adaptiveScrollTimeGate
        let dynamicMinorDeltaGate: CGFloat
        if inHighVelocityWindow {
            if directionChanged {
                dynamicMinorDeltaGate = gestureFast ? 12 : 8
            } else {
                dynamicMinorDeltaGate = gestureFast ? 24 : 18
            }
        } else {
            dynamicMinorDeltaGate = 3
        }
        let shouldPublishScrollPosition =
            delta > dynamicScrollDeltaThreshold ||
            ((now - lastScrollPositionPublishTimestamp) > dynamicScrollTimeGate && delta > dynamicMinorDeltaGate)
        let didEndProgrammaticBurst = !isProgrammaticEvent && hadProgrammaticInFlight
        let shouldSuppressProgrammaticSideEffects =
            !didEndProgrammaticBurst && isProgrammaticScrollActive(now: now)
        let shouldCommitScrollPosition =
            shouldPublishScrollPosition &&
            (!shouldSuppressProgrammaticSideEffects || didEndProgrammaticBurst)

        if shouldCommitScrollPosition {
            scrollPosition.wrappedValue = y
            lastScrollPositionPublishTimestamp = now
            if !shouldSuppressProgrammaticSideEffects {
                requestSaveIfNeeded(force: didEndProgrammaticBurst)
            }
        }

        if let progress, !shouldSuppressProgrammaticSideEffects {
            if inHighVelocityWindow && !didEndProgrammaticBurst {
                let minProgressInterval: TimeInterval
                if directionChanged {
                    minProgressInterval = gestureFast
                        ? min(adaptiveProgressTimeGate, 0.95)
                        : min(adaptiveProgressTimeGate, 0.85)
                } else {
                    minProgressInterval = gestureFast
                        ? max(adaptiveProgressTimeGate, 1.55)
                        : max(adaptiveProgressTimeGate, 1.35)
                }
                if (now - lastProgressTimestamp) >= minProgressInterval {
                    reportScrollProgressValue(progress)
                }
            } else {
                reportScrollProgressValue(progress, force: didEndProgrammaticBurst)
            }
        }

        let shouldTrackVisibleSection =
            inspectorPublisher.hasTableOfContents && isSectionTrackingRequested
        if !shouldSuppressProgrammaticSideEffects,
           shouldTrackVisibleSection,
           let sectionId = data["sectionId"] as? String {
            if inspectorPublisher.shouldPublishVisibleSection(sectionId, force: false) {
                onVisibleSectionChange?(sectionId)
            }
        }
    }

    func handleScrollPerfSnapshot(_ data: [String: Any]) {
        let longTasks = data["longTasks"] as? Int ?? 0
        let avgVelocity = data["avgVelocity"] as? Double ?? 0
        let postsPerSecond = data["postsPerSecond"] as? Double ?? 0

        let targetProfile: ScrollProfile
        if longTasks >= 2 {
            targetProfile = .economy
        } else if avgVelocity < 0.45 && postsPerSecond < 8.0 {
            targetProfile = .responsive
        } else {
            targetProfile = .balanced
        }

        applyScrollProfile(targetProfile)
    }

    func setupScrollObserver(for webView: WKWebView) {
        guard let scrollView = findScrollView(in: webView) else { return }

        cleanup()

        scrollView.contentView.postsBoundsChangedNotifications = true

        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self, weak webView] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                let now = Date().timeIntervalSinceReferenceDate
                if now - self.lastJSTelemetryTimestamp < 0.95 {
                    return
                }
                if self.isContentLoadInFlight {
                    return
                }
                if self.isProgrammaticScrollActive(now: now) {
                    return
                }
                if now < self.highVelocityUserScrollUntil {
                    return
                }

                let currentY = scrollView.contentView.bounds.origin.y
                if self.shouldIgnoreInitialTopTelemetry(y: currentY, progress: nil, now: now) {
                    return
                }
                self.lastKnownScrollY = currentY

                let delta = abs(self.scrollPosition.wrappedValue - currentY)
                let shouldPublishScrollPosition =
                    delta > self.adaptiveFallbackDeltaThreshold ||
                    ((now - self.lastScrollPositionPublishTimestamp) > self.adaptiveFallbackTimeGate && delta > 3)

                if shouldPublishScrollPosition {
                    self.scrollPosition.wrappedValue = currentY
                    self.lastScrollPositionPublishTimestamp = now
                    self.requestSaveIfNeeded()
                }

                self.reportScrollProgress(from: scrollView, currentY: currentY)

                if self.inspectorPublisher.hasTableOfContents,
                   self.isSectionTrackingRequested,
                   now - self.lastVisibleSectionPollTimestamp > 0.3,
                   let webView {
                    self.lastVisibleSectionPollTimestamp = now
                    self.publishVisibleSection(from: webView)
                }
            }
        }
    }

    func requestSaveIfNeeded(force: Bool = false) {
        let now = Date().timeIntervalSinceReferenceDate
        if !force, isProgrammaticScrollActive(now: now) {
            return
        }
        if !force, now < highVelocityUserScrollUntil {
            return
        }
        if force || (now - lastSaveRequestTimestamp) >= adaptiveSaveRequestInterval {
            lastSaveRequestTimestamp = now
            appState?.requestSave()
        }
    }

    func clearInitialRestoreTelemetryGuard() {
        initialTelemetryGuard = .inactive
    }

    func configureInitialRestoreTelemetryGuard(
        scrollY: CGFloat,
        fallbackProgress: Double,
        now: TimeInterval
    ) {
        initialTelemetryGuard = WebViewScrollRestoreController.InitialTelemetryGuard.configured(
            scrollY: scrollY,
            fallbackProgress: fallbackProgress,
            now: now
        )
    }

    func shouldIgnoreInitialTopTelemetry(y: CGFloat, progress: Double?, now: TimeInterval) -> Bool {
        initialTelemetryGuard.shouldIgnore(y: y, progress: progress, now: now)
    }

    func syncScrollTelemetryMode(on webView: WKWebView, force: Bool = false) {
        let desired = isSectionTrackingRequested
        guard force || lastAppliedSectionTrackingRequest != desired else { return }
        let script = "window.setScrollTelemetrySectionTrackingEnabled && window.setScrollTelemetrySectionTrackingEnabled(\(desired ? "true" : "false"));"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard error == nil else { return }
            self?.lastAppliedSectionTrackingRequest = desired
        }
    }

    func syncRestoreTelemetryMode(on webView: WKWebView, force: Bool = false) {
        let desired = isContentLoadInFlight
        guard force || lastAppliedRestoreTelemetryMode != desired else { return }
        let script = "window.setRestoreTelemetryMode && window.setRestoreTelemetryMode(\(desired ? "true" : "false"));"
        webView.evaluateJavaScript(script) { [weak self] _, error in
            guard error == nil else { return }
            self?.lastAppliedRestoreTelemetryMode = desired
        }
    }

    func applyScrollProfile(_ profile: ScrollProfile) {
        guard profile != currentScrollProfile else { return }
        currentScrollProfile = profile
        switch profile {
        case .responsive:
            adaptiveScrollDeltaThreshold = 12
            adaptiveScrollTimeGate = 0.75
            adaptiveProgressDeltaThreshold = 0.035
            adaptiveProgressTimeGate = 1.25
            adaptiveSaveRequestInterval = 3.0
            adaptiveFallbackDeltaThreshold = 13
            adaptiveFallbackTimeGate = 1.2
        case .balanced:
            adaptiveScrollDeltaThreshold = 14
            adaptiveScrollTimeGate = 0.9
            adaptiveProgressDeltaThreshold = 0.045
            adaptiveProgressTimeGate = 1.6
            adaptiveSaveRequestInterval = 3.4
            adaptiveFallbackDeltaThreshold = 14
            adaptiveFallbackTimeGate = 1.4
        case .economy:
            adaptiveScrollDeltaThreshold = 18
            adaptiveScrollTimeGate = 1.15
            adaptiveProgressDeltaThreshold = 0.06
            adaptiveProgressTimeGate = 2.1
            adaptiveSaveRequestInterval = 4.0
            adaptiveFallbackDeltaThreshold = 18
            adaptiveFallbackTimeGate = 1.8
        }
    }

    func reportScrollProgress(from scrollView: NSScrollView, currentY: CGFloat? = nil, force: Bool = false) {
        let contentHeight = scrollView.documentView?.bounds.height ?? 0
        let viewportHeight = scrollView.contentView.bounds.height
        let maxScroll = max(contentHeight - viewportHeight, 0)
        let offsetY = currentY ?? scrollView.contentView.bounds.origin.y
        let rawProgress = maxScroll > 0 ? Double(offsetY / maxScroll) : 1
        let clamped = min(max(rawProgress, 0), 1)
        reportScrollProgressValue(clamped, force: force)
    }

    func reportScrollProgressValue(_ progress: Double, force: Bool = false) {
        if isContentLoadInFlight {
            return
        }
        let clamped = min(max(progress, 0), 1)
        let now = Date().timeIntervalSinceReferenceDate
        if shouldIgnoreInitialTopTelemetry(y: lastKnownScrollY, progress: clamped, now: now) {
            return
        }
        let progressDelta = abs(clamped - lastReportedProgress)
        let timeDelta = now - lastProgressTimestamp
        if force || progressDelta >= adaptiveProgressDeltaThreshold || timeDelta >= adaptiveProgressTimeGate {
            lastReportedProgress = clamped
            lastProgressTimestamp = now
            onScrollProgress?(clamped)
        }
    }

    func findScrollView(in view: NSView) -> NSScrollView? {
        if let webView = view as? WKWebView {
            return webView.enclosingScrollView
        }
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let found = findScrollView(in: subview) {
                return found
            }
        }

        return nil
    }
}
