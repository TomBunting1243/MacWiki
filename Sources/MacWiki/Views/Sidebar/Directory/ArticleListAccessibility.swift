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
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityValue(isRead ? "Read" : "Unread")
                .accessibilityHint("Open \(title). Additional article controls and context menu actions are available.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
                .accessibilityAction(
                    named: Text(isRead ? "Mark as Unread" : "Mark as Read"),
                    onToggleRead
                )
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel(title)
                .accessibilityInputLabels([title])
                .accessibilityHint("Open \(title). Additional article controls and context menu actions are available.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction {
                    onOpen()
                }
        }
    }
}
