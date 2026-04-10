import Foundation
import Testing

@testable import MacWiki

struct WebViewScrollRestoreControllerTests {
    @Test func configuredGuardUnlocksAfterMeaningfulRestoreProgress() {
        var guardState = WebViewScrollRestoreController.InitialTelemetryGuard.configured(
            scrollY: 320,
            fallbackProgress: 0,
            now: 10
        )

        #expect(guardState.shouldIgnore(y: 0, progress: 0, now: 10.2) == true)
        #expect(guardState.shouldIgnore(y: 120, progress: 0.2, now: 10.4) == false)
        #expect(guardState.shouldIgnore(y: 140, progress: 0.24, now: 10.6) == false)
    }

    @Test func configuredGuardExpiresWhenNoRestoreArrives() {
        var guardState = WebViewScrollRestoreController.InitialTelemetryGuard.configured(
            scrollY: 220,
            fallbackProgress: 0.42,
            now: 2
        )

        #expect(guardState.shouldIgnore(y: 0, progress: 0, now: 2.5) == true)
        #expect(guardState.shouldIgnore(y: 0, progress: 0, now: 6.2) == false)
    }

    @Test func finalRevealProbeAlwaysReveals() {
        let shouldReveal = WebViewScrollRestoreController.shouldRevealAfterRestoreProbe(
            probeResult: nil,
            desiredY: 240,
            fallbackProgress: 0,
            isFinalProbe: true,
            preferImmediateReveal: false
        )

        #expect(shouldReveal == true)
    }
}
