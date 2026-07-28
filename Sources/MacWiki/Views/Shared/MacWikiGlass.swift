import SwiftUI

enum MacWikiGlassRuntime {
    static let forceLegacyFallbackKey = "forceLegacyGlassFallback"

    struct SurfacePolicy: Equatable {
        let usesNativeGlass: Bool
        let usesOpaqueBackground: Bool
        let allowsDepth: Bool
    }

    static func surfacePolicy(
        isEnabled: Bool,
        forceLegacyFallback: Bool,
        personalization: MacWikiAccessibilityPersonalization
    ) -> SurfacePolicy {
        let usesOpaqueBackground =
            personalization.reduceTransparency ||
            personalization.colorSchemeContrast == .increased
        let supportsNativeGlass: Bool
        if #available(macOS 26, *) {
            supportsNativeGlass = true
        } else {
            supportsNativeGlass = false
        }

        return SurfacePolicy(
            usesNativeGlass:
                supportsNativeGlass &&
                isEnabled &&
                !forceLegacyFallback &&
                !usesOpaqueBackground,
            usesOpaqueBackground: usesOpaqueBackground,
            allowsDepth: !usesOpaqueBackground
        )
    }

    /// Returns whether custom chrome should use native Liquid Glass.
    ///
    /// The personalization value is the app's single accessibility boundary. It contains the
    /// system values in production and isolated overrides in QA, so every surface follows the
    /// same policy without mutating global macOS settings.
    static func usesNativeGlass(
        isEnabled: Bool,
        forceLegacyFallback: Bool,
        personalization: MacWikiAccessibilityPersonalization
    ) -> Bool {
        surfacePolicy(
            isEnabled: isEnabled,
            forceLegacyFallback: forceLegacyFallback,
            personalization: personalization
        ).usesNativeGlass
    }

    static func usesNativeGlass(
        forceLegacyFallback: Bool,
        personalization: MacWikiAccessibilityPersonalization
    ) -> Bool {
        usesNativeGlass(
            isEnabled: true,
            forceLegacyFallback: forceLegacyFallback,
            personalization: personalization
        )
    }
}

struct MacWikiGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26, *) {
            // Keep the container structurally stable while preferences or accessibility
            // settings change. Leaf surfaces own the policy that enables glass.
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}
