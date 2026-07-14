import SwiftUI

/// macOS 26 fallback for tab reordering. macOS 27 uses SwiftUI's native
/// reorder container, so this gesture must be absent there or it competes
/// with button clicks and the system drag recognizer.
struct LegacyTabDragModifier: ViewModifier {
    let isEnabled: Bool
    let minimumDistance: CGFloat
    let onChanged: (CGFloat, CGFloat) -> Void
    let onEnded: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.highPriorityGesture(
                DragGesture(
                    minimumDistance: minimumDistance,
                    coordinateSpace: .named("TabBarSpace")
                )
                .onChanged { value in
                    onChanged(value.translation.width, value.location.x)
                }
                .onEnded { _ in
                    onEnded()
                }
            )
        } else {
            content
        }
    }
}
