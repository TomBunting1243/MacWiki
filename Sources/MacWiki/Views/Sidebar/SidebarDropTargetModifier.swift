import SwiftUI

struct SidebarDropTargetModifier: ViewModifier {
    @Environment(\.macWikiAccessibilityPersonalization.differentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    let isTargeted: Bool

    private var fillColor: Color {
        guard isTargeted else { return .clear }
        let isKeyWindow = controlActiveState == .key
        if colorScheme == .dark {
            return Color.accentColor.opacity(isKeyWindow ? 0.14 : 0.09)
        }
        return Color.accentColor.opacity(isKeyWindow ? 0.11 : 0.07)
    }

    private var strokeColor: Color {
        guard isTargeted else { return .clear }
        if differentiateWithoutColor {
            return colorScheme == .dark ? Color.white.opacity(0.88) : Color.primary.opacity(0.78)
        }
        let isKeyWindow = controlActiveState == .key
        return Color.accentColor.opacity(isKeyWindow ? 0.82 : 0.60)
    }

    private var lineWidth: CGFloat {
        differentiateWithoutColor ? 1.5 : 1
    }

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: lineWidth)
                    }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isTargeted)
    }
}

extension View {
    func sidebarDropTargetStyle(isTargeted: Bool) -> some View {
        modifier(SidebarDropTargetModifier(isTargeted: isTargeted))
    }
}
