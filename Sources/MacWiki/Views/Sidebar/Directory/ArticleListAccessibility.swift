import AppKit
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
        content
            .accessibilityHidden(true)
            .background {
                HStack(spacing: 0) {
                    AccessibleArticleRowProxy(
                        title: title,
                        value: value,
                        help: "Open article",
                        action: onOpen
                    )
                    if let onToggleRead {
                        AccessibleArticleRowProxy(
                            title: isRead ? "Mark as unread" : "Mark as read",
                            value: isRead ? "Read" : "Unread",
                            help: isRead ? "Mark this article as unread" : "Mark this article as read",
                            action: onToggleRead
                        )
                    }
                }
            }
    }
}

/// A native accessibility-only proxy for article rows. SwiftUI's macOS List
/// bridge drops dynamic Button titles in this nested composition, even when an
/// explicit accessibility label or representation is supplied. The proxy does
/// not draw or participate in hit testing, so SwiftUI keeps all pointer,
/// keyboard, drag, and context-menu behavior.
private struct AccessibleArticleRowProxy: NSViewRepresentable {
    let title: String
    let value: String
    let help: String
    let action: () -> Void

    func makeNSView(context: Context) -> ProxyView {
        ProxyView()
    }

    func updateNSView(_ view: ProxyView, context: Context) {
        view.action = action
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.button)
        view.setAccessibilityTitle(title)
        view.setAccessibilityLabel(title)
        view.setAccessibilityValue(value)
        view.setAccessibilityHelp(help)
    }

    @MainActor
    final class ProxyView: NSView {
        var action: (() -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func accessibilityPerformPress() -> Bool {
            guard let action else { return false }
            action()
            return true
        }
    }
}
