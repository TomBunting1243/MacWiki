import CoreGraphics
import Foundation

struct ReaderPromptPolicy {
    private var promptEligibilityTimestamp: TimeInterval = 0
    private var hasUserScrolledSinceLoad = false
    private var userScrollTravelSinceLoad: CGFloat = 0
    private var sessionStartProgress: Double = 0
    private var minimumPromptProgressToShow: Double = 0.93

    mutating func resetForSession(
        startProgress: Double,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        hasUserScrolledSinceLoad = false
        userScrollTravelSinceLoad = 0
        sessionStartProgress = startProgress
        minimumPromptProgressToShow = min(max(sessionStartProgress + 0.10, 0.93), 0.992)
        promptEligibilityTimestamp = now + 1.35
    }

    mutating func noteScrollChange(
        oldValue: CGFloat,
        newValue: CGFloat,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        guard now >= promptEligibilityTimestamp else { return }

        let delta = abs(newValue - oldValue)
        if delta > 3, delta < 140 {
            userScrollTravelSinceLoad += delta
        }
        if userScrollTravelSinceLoad > 220 {
            hasUserScrolledSinceLoad = true
        }
    }

    func shouldShowPrompt(
        forProgress progress: Double,
        isArticleUnread: Bool,
        isPromptAlreadyVisible: Bool
    ) -> Bool {
        guard isArticleUnread, !isPromptAlreadyVisible, hasUserScrolledSinceLoad else {
            return false
        }
        return (progress - sessionStartProgress) >= 0.06 && progress >= minimumPromptProgressToShow
    }
}
