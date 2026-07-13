import SwiftUI

struct ArticleListAccessibilityModifier: ViewModifier {
    let title: String
    let onOpen: () -> Void
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityValue(title)
                .accessibilityHint("Open \(title). Use the context menu for read status and organization actions.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
        } else {
            content
        }
    }
}
