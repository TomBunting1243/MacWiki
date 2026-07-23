import SwiftUI

enum TimeMachineVisualLanguage {
    static let ultraviolet = Color(red: 0.58, green: 0.22, blue: 1.0)
    static let electricViolet = Color(red: 0.76, green: 0.28, blue: 1.0)
    static let temporalIndigo = Color(red: 0.30, green: 0.24, blue: 0.96)
    static let neonPink = Color(red: 1.0, green: 0.26, blue: 0.76)

    static let accentGradient = LinearGradient(
        colors: [electricViolet, ultraviolet, temporalIndigo],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let surfaceTints: [Color] = [
        electricViolet.opacity(0.16),
        temporalIndigo.opacity(0.10),
        neonPink.opacity(0.045),
    ]
}

struct TimeMachineAccentMark: View {
    let isActive: Bool

    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            TimeMachineVisualLanguage.electricViolet.opacity(0.34),
                            TimeMachineVisualLanguage.temporalIndigo.opacity(0.10),
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 18
                    )
                )

            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TimeMachineVisualLanguage.electricViolet)
                .symbolVariant(isActive ? .fill : .none)
                .rotationEffect(reduceMotion || !isActive ? .zero : .degrees(-8))
        }
        .frame(width: 30, height: 30)
        .overlay {
            Circle()
                .strokeBorder(
                    TimeMachineVisualLanguage.electricViolet.opacity(0.30),
                    lineWidth: 0.8
                )
        }
        .accessibilityHidden(true)
    }
}

private struct TimeMachineSurfaceChromeModifier: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.macWikiAccessibilityPersonalization) private var personalization

    func body(content: Content) -> some View {
        content
            .discoverSurfaceChrome(
                cornerRadius: cornerRadius,
                material: .thin,
                tintColors: TimeMachineVisualLanguage.surfaceTints,
                borderColor: TimeMachineVisualLanguage.electricViolet,
                borderOpacity: personalization.colorSchemeContrast == .increased ? 0.72 : 0.38,
                borderWidth: personalization.colorSchemeContrast == .increased ? 1.2 : 0.8,
                shadowOpacity: personalization.reduceTransparency ? 0 : 0.16,
                shadowRadius: 18,
                shadowY: 7
            )
            .overlay(alignment: .top) {
                Capsule(style: .continuous)
                    .fill(TimeMachineVisualLanguage.accentGradient)
                    .frame(height: personalization.colorSchemeContrast == .increased ? 2 : 1.5)
                    .padding(.horizontal, 18)
                    .opacity(personalization.differentiateWithoutColor ? 1 : 0.82)
            }
    }
}

extension View {
    func timeMachineSurfaceChrome(cornerRadius: CGFloat) -> some View {
        modifier(TimeMachineSurfaceChromeModifier(cornerRadius: cornerRadius))
    }
}
