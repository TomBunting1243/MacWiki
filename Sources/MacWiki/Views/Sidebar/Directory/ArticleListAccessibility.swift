import SwiftUI

struct ArticleListAccessibilityModifier: ViewModifier {
    let title: String
    let isRead: Bool
    let onOpen: () -> Void
    let onToggleRead: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let onToggleRead {
            content
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityValue(title)
                .accessibilityHint("Open \(title). Use the context menu for read status and organization actions.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
                .accessibilityAction(
                    named: Text(isRead ? "Mark as unread" : "Mark as read"),
                    onToggleRead
                )
        } else {
            content
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityValue(title)
                .accessibilityHint("Open \(title). Use the context menu for organization actions.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
        }
    }
}
