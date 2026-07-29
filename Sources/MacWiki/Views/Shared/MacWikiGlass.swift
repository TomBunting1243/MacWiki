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

    /// Policy for content and transient surfaces that intentionally use system material
    /// instead of interactive Liquid Glass while sharing the same accessibility boundary.
    static func materialSurfacePolicy(
        personalization: MacWikiAccessibilityPersonalization
    ) -> SurfacePolicy {
        surfacePolicy(
            isEnabled: false,
            forceLegacyFallback: false,
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

private struct MacWikiDragPreviewSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = MacWikiGlassRuntime.materialSurfacePolicy(personalization: personalization)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .padding(8)
            .background {
                if policy.usesOpaqueBackground {
                    shape.fill(Color(nsColor: .controlBackgroundColor))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity(
                        personalization.colorSchemeContrast == .increased ? 0.28 : 0.08
                    ),
                    lineWidth: personalization.colorSchemeContrast == .increased ? 1 : 0.7
                )
            }
    }
}

extension View {
    /// Compact, accessibility-aware system material used only for custom drag previews.
    func macWikiDragPreviewSurface(cornerRadius: CGFloat = 8) -> some View {
        modifier(MacWikiDragPreviewSurfaceModifier(cornerRadius: cornerRadius))
    }
}
