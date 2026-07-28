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
        usesOpaqueBackground =
            personalization.reduceTransparency ||
            personalization.colorSchemeContrast == .increased
        usesNativeGlass = nativeGlassEnabled && !usesOpaqueBackground

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

        shadowMultiplier = usesOpaqueBackground ? 0 : 1
    }
}

private struct DiscoverRoundedSurfaceChromeModifier: ViewModifier {
    let isEnabled: Bool
    let cornerRadius: CGFloat
    let material: DiscoverSurfaceMaterial
    let tintColors: [Color]
    let borderColor: Color
    let baseBorderOpacity: Double
    let baseBorderWidth: CGFloat
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    @ViewBuilder
    func body(content: Content) -> some View {
        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: MacWikiGlassRuntime.usesNativeGlass(
                isEnabled: liquidGlassChrome,
                forceLegacyFallback: forceLegacyGlassFallback,
                personalization: personalization
            ),
            baseBorderOpacity: baseBorderOpacity
        )

        if isEnabled {
            content
                .background {
                    roundedBackground(policy: policy)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            borderColor.opacity(policy.borderOpacity),
                            lineWidth: max(baseBorderWidth, policy.borderWidth)
                        )
                }
                .shadow(
                    color: Color.black.opacity(shadowOpacity * policy.shadowMultiplier),
                    radius: shadowRadius,
                    y: shadowY
                )
        } else {
            content
        }
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

    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: MacWikiGlassRuntime.usesNativeGlass(
                isEnabled: liquidGlassChrome,
                forceLegacyFallback: forceLegacyGlassFallback,
                personalization: personalization
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

private struct DiscoverCircleSurfaceChromeModifier: ViewModifier {
    let material: DiscoverSurfaceMaterial
    let borderColor: Color
    let baseBorderOpacity: Double

    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = DiscoverSurfacePolicy(
            personalization: personalization,
            nativeGlassEnabled: MacWikiGlassRuntime.usesNativeGlass(
                isEnabled: liquidGlassChrome,
                forceLegacyFallback: forceLegacyGlassFallback,
                personalization: personalization
            ),
            baseBorderOpacity: baseBorderOpacity
        )

        content
            .background { circleBackground(policy: policy) }
            .overlay {
                Circle()
                    .strokeBorder(
                        borderColor.opacity(policy.borderOpacity),
                        lineWidth: policy.borderWidth
                    )
            }
    }

    @ViewBuilder
    private func circleBackground(policy: DiscoverSurfacePolicy) -> some View {
        let shape = Circle()

        if policy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else if policy.usesNativeGlass {
            if #available(macOS 26, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular, in: .circle)
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
        isEnabled: Bool = true,
        cornerRadius: CGFloat,
        material: DiscoverSurfaceMaterial = .thin,
        tintColors: [Color] = [],
        borderColor: Color = Color(nsColor: .separatorColor),
        borderOpacity: Double = 0.34,
        borderWidth: CGFloat = 0.7,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            DiscoverRoundedSurfaceChromeModifier(
                isEnabled: isEnabled,
                cornerRadius: cornerRadius,
                material: material,
                tintColors: tintColors,
                borderColor: borderColor,
                baseBorderOpacity: borderOpacity,
                baseBorderWidth: borderWidth,
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

    func discoverCircleSurfaceChrome(
        material: DiscoverSurfaceMaterial = .thin,
        borderColor: Color = Color(nsColor: .separatorColor),
        borderOpacity: Double = 0.35
    ) -> some View {
        modifier(
            DiscoverCircleSurfaceChromeModifier(
                material: material,
                borderColor: borderColor,
                baseBorderOpacity: borderOpacity
            )
        )
    }
}
