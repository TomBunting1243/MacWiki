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
                .accessibilityValue("\(title), \(isRead ? "Read" : "Unread")")
                .accessibilityHint("Open \(title). Use the context menu for read status and organization actions.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
                .accessibilityAction(
                    named: Text("Toggle Read Status"),
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
