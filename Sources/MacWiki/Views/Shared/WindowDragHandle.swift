import SwiftUI

/// Reserved top-lane spacer used by chrome views.
///
/// Drag behavior is handled by the native SwiftUI window background policy in
/// `MacWikiApp` to avoid overlapping custom drag surfaces.
struct WindowDragHandle: View {
    var minLength: CGFloat = 24

    var body: some View {
        Color.clear
            .frame(minWidth: minLength)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
