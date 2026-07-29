import SwiftUI

enum ReaderInspectorSurfaceMaterial {
    case ultraThin
    case thin
    case regular
}

struct ReaderInspectorSurfacePolicy: Equatable {
    let usesOpaqueBackground: Bool
    let borderOpacity: Double
    let borderWidth: CGFloat
    let shadowMultiplier: Double

    init(
        personalization: MacWikiAccessibilityPersonalization,
        baseBorderOpacity: Double,
        baseBorderWidth: CGFloat
    ) {
        // Inspector cards intentionally use material rather than interactive Liquid Glass,
        // but their accessibility behavior must still come from the app-wide surface policy.
        let surfacePolicy = MacWikiGlassRuntime.materialSurfacePolicy(
            personalization: personalization
        )
        usesOpaqueBackground = surfacePolicy.usesOpaqueBackground

        if personalization.colorSchemeContrast == .increased {
            borderOpacity = max(baseBorderOpacity, 0.28)
            borderWidth = max(baseBorderWidth, 1)
        } else if personalization.reduceTransparency {
            borderOpacity = max(baseBorderOpacity, 0.16)
            borderWidth = max(baseBorderWidth, 0.8)
        } else {
            borderOpacity = baseBorderOpacity
            borderWidth = baseBorderWidth
        }

        shadowMultiplier = surfacePolicy.allowsDepth ? 1 : 0
    }
}

private struct ReaderInspectorRoundedSurfaceChromeModifier: ViewModifier {
    let cornerRadius: CGFloat
    let material: ReaderInspectorSurfaceMaterial
    let materialOpacity: Double
    let baseBorderOpacity: Double
    let baseBorderWidth: CGFloat
    let highlightOpacity: Double
    let shadowOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = ReaderInspectorSurfacePolicy(
            personalization: personalization,
            baseBorderOpacity: baseBorderOpacity,
            baseBorderWidth: baseBorderWidth
        )

        content
            .background { background(policy: policy) }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(policy.borderOpacity),
                        lineWidth: policy.borderWidth
                    )
            }
            .shadow(
                color: .black.opacity(shadowOpacity * policy.shadowMultiplier),
                radius: shadowRadius,
                y: shadowY
            )
    }

    @ViewBuilder
    private func background(policy: ReaderInspectorSurfacePolicy) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        if policy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            materialBackground(shape: shape)
                .opacity(materialOpacity)
                .overlay {
                    if highlightOpacity > 0 {
                        shape
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(highlightOpacity),
                                        Color.white.opacity(highlightOpacity * 0.15),
                                        Color.clear
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.screen)
                    }
                }
        }
    }

    @ViewBuilder
    private func materialBackground(shape: RoundedRectangle) -> some View {
        switch material {
        case .ultraThin:
            shape.fill(.ultraThinMaterial)
        case .thin:
            shape.fill(.thinMaterial)
        case .regular:
            shape.fill(.regularMaterial)
        }
    }
}

private struct ReaderInspectorCapsuleSurfaceChromeModifier: ViewModifier {
    let material: ReaderInspectorSurfaceMaterial
    let baseBorderOpacity: Double
    let baseBorderWidth: CGFloat

    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        let policy = ReaderInspectorSurfacePolicy(
            personalization: personalization,
            baseBorderOpacity: baseBorderOpacity,
            baseBorderWidth: baseBorderWidth
        )

        content
            .background { background(policy: policy) }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(policy.borderOpacity),
                        lineWidth: policy.borderWidth
                    )
            }
    }

    @ViewBuilder
    private func background(policy: ReaderInspectorSurfacePolicy) -> some View {
        let shape = Capsule(style: .continuous)

        if policy.usesOpaqueBackground {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        } else {
            switch material {
            case .ultraThin:
                shape.fill(.ultraThinMaterial)
            case .thin:
                shape.fill(.thinMaterial)
            case .regular:
                shape.fill(.regularMaterial)
            }
        }
    }
}

extension View {
    func readerInspectorRoundedSurface(
        cornerRadius: CGFloat,
        material: ReaderInspectorSurfaceMaterial,
        materialOpacity: Double = 1,
        baseBorderOpacity: Double = 0.08,
        baseBorderWidth: CGFloat = 0.7,
        highlightOpacity: Double = 0,
        shadowOpacity: Double = 0,
        shadowRadius: CGFloat = 0,
        shadowY: CGFloat = 0
    ) -> some View {
        modifier(
            ReaderInspectorRoundedSurfaceChromeModifier(
                cornerRadius: cornerRadius,
                material: material,
                materialOpacity: materialOpacity,
                baseBorderOpacity: baseBorderOpacity,
                baseBorderWidth: baseBorderWidth,
                highlightOpacity: highlightOpacity,
                shadowOpacity: shadowOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }

    func readerInspectorCapsuleSurface(
        material: ReaderInspectorSurfaceMaterial,
        baseBorderOpacity: Double = 0.08,
        baseBorderWidth: CGFloat = 0.7
    ) -> some View {
        modifier(
            ReaderInspectorCapsuleSurfaceChromeModifier(
                material: material,
                baseBorderOpacity: baseBorderOpacity,
                baseBorderWidth: baseBorderWidth
            )
        )
    }
}
