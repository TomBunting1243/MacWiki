import SwiftUI

/// A bounded, view-scoped tab reorder gesture shared by macOS 26 and 27.
/// The model commit remains in `TabBarView`; this modifier owns only pointer
/// recognition so button, context-menu, animation, and persistence concerns
/// stay separated.
struct TabReorderDragModifier: ViewModifier {
    let minimumDistance: CGFloat
    let onChanged: (CGFloat, CGFloat) -> Void
    let onEnded: () -> Void

    func body(content: Content) -> some View {
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
    }
}
