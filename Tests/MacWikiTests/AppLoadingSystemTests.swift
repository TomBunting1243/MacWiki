import AppKit
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct AppLoadingSystemTests {
    @Test func accessibilityPolicySelectsOpaqueBackgroundsWithoutDepthAndStrongerBorders() {
        let standard = AppLoadingSurfacePolicy(personalization: .standard)
        #expect(!standard.usesOpaqueBackground)
        #expect(standard.statusBorderWidth == 0.8)
        #expect(standard.surfaceBorderWidth == 0.9)
        #expect(standard.shadowMultiplier == 1)

        let reduceTransparency = AppLoadingSurfacePolicy(
            personalization: MacWikiAccessibilityPersonalization(
                reduceMotion: false,
                reduceTransparency: true,
                differentiateWithoutColor: false,
                colorSchemeContrast: .standard
            )
        )
        #expect(reduceTransparency.usesOpaqueBackground)
        #expect(reduceTransparency.statusBorderWidth == 0.8)
        #expect(reduceTransparency.surfaceBorderWidth == 0.9)
        #expect(reduceTransparency.shadowMultiplier == 0)

        let increasedContrast = AppLoadingSurfacePolicy(
            personalization: MacWikiAccessibilityPersonalization(
                reduceMotion: false,
                reduceTransparency: false,
                differentiateWithoutColor: false,
                colorSchemeContrast: .increased
            )
        )
        #expect(increasedContrast.usesOpaqueBackground)
        #expect(increasedContrast.statusBorderWidth == 1.2)
        #expect(increasedContrast.surfaceBorderWidth == 1.4)
        #expect(increasedContrast.shadowMultiplier == 0)
    }

    @Test func reduceMotionDoesNotAlterSurfaceAppearancePolicy() {
        let reduceMotion = MacWikiAccessibilityPersonalization(
            reduceMotion: true,
            reduceTransparency: false,
            differentiateWithoutColor: false,
            colorSchemeContrast: .standard
        )

        #expect(
            AppLoadingSurfacePolicy(personalization: reduceMotion) ==
                AppLoadingSurfacePolicy(personalization: .standard)
        )
    }

    @Test func activityMarkRendersANativeProgressIndicator() throws {
        let activityMark = AppLoadingActivityMark(
            accessibilityLabel: "Loading Search Results",
            compact: false
        )

        let hostingView = NSHostingView(rootView: activityMark)
        hostingView.frame = CGRect(x: 0, y: 0, width: 80, height: 48)
        hostingView.layoutSubtreeIfNeeded()

        let indicator = try #require(
            firstDescendant(of: NSProgressIndicator.self, in: hostingView)
        )
        #expect(indicator.isIndeterminate)
    }

    private func firstDescendant<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> ViewType? {
        if let match = root as? ViewType {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: type, in: subview) {
                return match
            }
        }
        return nil
    }
}
