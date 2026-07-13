import SwiftUI

enum ArticleListAccessibilityStatus {
    static func value(
        isRead: Bool,
        progress: Double,
        isCurrent: Bool,
        isSelected: Bool,
        labelName: String?
    ) -> String {
        var states = [isRead ? "Read" : "Unread"]
        let boundedProgress = min(max(progress, 0), 1)
        if boundedProgress > 0 {
            states.append("\(Int((boundedProgress * 100).rounded()))% read")
        }
        if isCurrent {
            states.append("Open in reader")
        }
        if isSelected {
            states.append("Selected")
        }
        if let labelName, !labelName.isEmpty {
            states.append("Label \(labelName)")
        }
        return states.joined(separator: ", ")
    }
}

struct ArticleListAccessibilityModifier: ViewModifier {
    let title: String
    let value: String
    let isRead: Bool
    let onOpen: () -> Void
    let onToggleRead: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        let semanticRow = Button(title, action: onOpen)
            .accessibilityLabel(title)
            .accessibilityInputLabels([title])
            .accessibilityValue("\(title), \(value)")
            .accessibilityHint("Open \(title)")

        if let onToggleRead {
            content.accessibilityRepresentation {
                semanticRow.accessibilityAction(
                    named: Text(isRead ? "Mark as unread" : "Mark as read"),
                    onToggleRead
                )
            }
        } else {
            content.accessibilityRepresentation {
                semanticRow
            }
        }
    }
}
