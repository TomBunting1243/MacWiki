import SwiftUI

enum DiscoverSurfaceMaterial {
    case thin
    case regular
}

struct DiscoverSurfacePolicy: Equatable {
    let usesOpaqueBackground: Bool
    let usesNativeGlass: Bool
    let borderOpacity: Double
    let borderWidth: CGFloat
    let shadowMultiplier: Double

    init(
        personalization: MacWikiAccessibilityPersonalization,
        nativeGlassEnabled: Bool,
        baseBorderOpacity: Double
    ) {
        usesOpaqueBackground = personalization.reduceTransparency
        usesNativeGlass = nativeGlassEnabled && !personalization.reduceTransparency

        if personalization.colorSchemeContrast == .increased {
            borderOpacity = max(baseBorderOpacity, 0.62)
            borderWidth = 1
        } else if personalization.reduceTransparency {
            borderOpacity = max(baseBorderOpacity, 0.48)
            borderWidth = 0.8
        } else {
            borderOpacity = baseBorderOpacity
            borderWidth = 0.7
        }

        shadowMultiplier = personalization.reduceTransparency ? 0 : 1
    }
}

private struct DiscoverRoundedSurfaceChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: DiscoverSurfaceMaterial
    let tintColors: [Color]
    let baseBorderOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: MacWikiGlassRuntime.usesNativeGlass(
                forceLegacyFallback: forceLegacyGlassFallback
            ),
            baseBorderOpacity: baseBorderOpacity
        )

        content
            .background {
                roundedBackground(policy: policy)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(policy.borderOpacity),
                        lineWidth: policy.borderWidth
                    )
            }
            .shadow(
                color: Color.black.opacity(shadowOpacity * policy.shadowMultiplier),
                radius: shadowRadius,
                y: shadowY
            )
    }

    @ViewBuilder
    private func roundedBackground(policy: DiscoverSurfacePolicy) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if policy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
                .overlay { tintOverlay(shape: shape) }
        } else if policy.usesNativeGlass {
            if #available(macOS 26, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
                    .overlay { tintOverlay(shape: shape) }
            }
        } else {
            switch material {
            case .thin:
                shape.fill(.thinMaterial)
                    .overlay { tintOverlay(shape: shape) }
            case .regular:
                shape.fill(.regularMaterial)
                    .overlay { tintOverlay(shape: shape) }
            }
        }
    }

    @ViewBuilder
    private func tintOverlay(shape: RoundedRectangle) -> some View {
        if !tintColors.isEmpty {
            shape.fill(
                LinearGradient(
                    colors: tintColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }
}

private struct DiscoverCapsuleSurfaceChromeModifier: ViewModifier {
    let material: DiscoverSurfaceMaterial
    let baseBorderOpacity: Double

    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: MacWikiGlassRuntime.usesNativeGlass(
                forceLegacyFallback: forceLegacyGlassFallback
            ),
            baseBorderOpacity: baseBorderOpacity
        )

        content
            .background { capsuleBackground(policy: policy) }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color(nsColor: .separatorColor).opacity(policy.borderOpacity),
                        lineWidth: policy.borderWidth
                    )
            }
    }

    @ViewBuilder
    private func capsuleBackground(policy: DiscoverSurfacePolicy) -> some View {
        let shape = Capsule(style: .continuous)

        if policy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else if policy.usesNativeGlass {
            if #available(macOS 26, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: .capsule)
            }
        } else {
            switch material {
            case .thin:
                shape.fill(.thinMaterial)
            case .regular:
                shape.fill(.regularMaterial)
            }
        }
    }
}

extension View {
    func discoverSurfaceChrome(
        cornerRadius: CGFloat,
        material: DiscoverSurfaceMaterial = .thin,
        tintColors: [Color] = [],
        borderOpacity: Double = 0.34,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            DiscoverRoundedSurfaceChromeModifier(
                cornerRadius: cornerRadius,
                material: material,
                tintColors: tintColors,
                baseBorderOpacity: borderOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func discoverCapsuleSurfaceChrome(
        material: DiscoverSurfaceMaterial = .thin,
        borderOpacity: Double = 0.35
    ) -> some View {
        modifier(
            DiscoverCapsuleSurfaceChromeModifier(
                material: material,
                baseBorderOpacity: borderOpacity
            )
        )
    }
}
