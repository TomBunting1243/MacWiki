import Foundation

enum WebViewScrollRestoreController {
    struct InitialTelemetryGuard {
        var suppressInitialScrollPersistenceUntil: TimeInterval = 0
        var hasPendingNonZeroRestore = false
        var pendingNonZeroRestoreDeadline: TimeInterval = 0
        var pendingRestoreUnlockProgress: Double = 0.08
        var pendingRestoreUnlockY: CGFloat = 80

        static var inactive: InitialTelemetryGuard {
            InitialTelemetryGuard()
        }

        static func configured(
            scrollY: CGFloat,
            fallbackProgress: Double,
            now: TimeInterval
        ) -> InitialTelemetryGuard {
            let clampedFallback = min(max(fallbackProgress, 0), 1)
            let shouldGuardInitialTopTelemetry = scrollY > 6 || clampedFallback > 0.01
            guard shouldGuardInitialTopTelemetry else {
                return .inactive
            }

            var guardState = InitialTelemetryGuard()
            guardState.suppressInitialScrollPersistenceUntil = now + 1.15
            guardState.hasPendingNonZeroRestore = true
            guardState.pendingNonZeroRestoreDeadline = now + 3.8

            if scrollY > 6 {
                guardState.pendingRestoreUnlockY = min(max(scrollY * 0.24, 80), 520)
            } else if clampedFallback > 0.35 {
                guardState.pendingRestoreUnlockY = 120
            } else {
                guardState.pendingRestoreUnlockY = 80
            }

            if clampedFallback > 0.01 {
                guardState.pendingRestoreUnlockProgress = min(max(clampedFallback * 0.55, 0.08), 0.30)
            } else {
                guardState.pendingRestoreUnlockProgress = 0.12
            }

            return guardState
        }

        mutating func shouldIgnore(y: CGFloat, progress: Double?, now: TimeInterval) -> Bool {
            if hasPendingNonZeroRestore {
                let clampedProgress = min(max(progress ?? 0, 0), 1)
                let unlockedByY = y >= pendingRestoreUnlockY
                let unlockedByProgress = clampedProgress >= pendingRestoreUnlockProgress && y > 12
                let suspiciousTopCompletion = y < 14 && clampedProgress > 0.97
                let remainsNearTop = y < 14 && clampedProgress < 0.08

                if unlockedByY || unlockedByProgress {
                    hasPendingNonZeroRestore = false
                    pendingNonZeroRestoreDeadline = 0
                    suppressInitialScrollPersistenceUntil = 0
                } else if now < pendingNonZeroRestoreDeadline, (remainsNearTop || suspiciousTopCompletion) {
                    return true
                } else if now < pendingNonZeroRestoreDeadline {
                    return true
                } else {
                    hasPendingNonZeroRestore = false
                    pendingNonZeroRestoreDeadline = 0
                }
            }

            return now < suppressInitialScrollPersistenceUntil
        }
    }

    static func retryDelays(preferImmediateReveal: Bool) -> [TimeInterval] {
        preferImmediateReveal ? [0.03, 0.09, 0.2, 0.38, 0.66, 1.0] : [0.08, 0.24, 0.55, 1.1, 1.9, 2.8]
    }

    static func revealCheckpoints(preferImmediateReveal: Bool) -> [TimeInterval] {
        preferImmediateReveal ? [0.02, 0.06, 0.13, 0.24, 0.42, 0.74] : [0.16, 0.38, 0.82, 1.45, 2.35, 3.35]
    }

    static func shouldRevealAfterRestoreProbe(
        probeResult: Any?,
        desiredY: CGFloat,
        fallbackProgress: Double,
        isFinalProbe: Bool,
        preferImmediateReveal: Bool
    ) -> Bool {
        if isFinalProbe {
            return true
        }

        guard let data = probeResult as? [String: Any] else {
            return false
        }

        let measuredY = (data["y"] as? Double).map { CGFloat($0) } ?? 0
        let measuredProgress = min(max(data["progress"] as? Double ?? 0, 0), 1)
        let maxScroll = data["maxScroll"] as? Double ?? 0

        if maxScroll <= 1 {
            return true
        }

        if desiredY > 6 {
            let positionTolerance = max(44, desiredY * 0.09)
            if abs(measuredY - desiredY) <= positionTolerance {
                return true
            }
            if measuredY >= desiredY * (preferImmediateReveal ? 0.64 : 0.78) {
                return true
            }
        } else if fallbackProgress > 0.01 {
            let clampedTargetProgress = min(max(fallbackProgress, 0), 1)
            if abs(measuredProgress - clampedTargetProgress) <= 0.07 {
                return true
            }
            if measuredProgress >= clampedTargetProgress * (preferImmediateReveal ? 0.68 : 0.82) {
                return true
            }
        } else {
            return true
        }

        return false
    }
}
