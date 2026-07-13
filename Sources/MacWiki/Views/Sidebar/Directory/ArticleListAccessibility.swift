import SwiftUI

struct ArticleListAccessibilityModifier: ViewModifier {
    let title: String
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                Button(action: onOpen) {
                    Color.clear
                }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityValue(title)
                .accessibilityHint("Open \(title). Use the context menu for read status and organization actions.")
            }
    }
}
