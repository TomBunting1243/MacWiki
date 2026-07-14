import SwiftUI

struct SidebarSearchStateView: View {
    let title: Text
    let message: Text
    let systemImage: String
    let style: ColumnEmptyStateStyle
    let actionTitle: LocalizedStringResource?
    let action: (() -> Void)?

    init(
        title: LocalizedStringResource,
        message: LocalizedStringResource,
        systemImage: String,
        style: ColumnEmptyStateStyle = .standard,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: Text(title),
            message: Text(message),
            systemImage: systemImage,
            style: style,
            actionTitle: actionTitle,
            action: action
        )
    }

    init(
        title: LocalizedStringResource,
        message: Text,
        systemImage: String,
        style: ColumnEmptyStateStyle = .standard,
        actionTitle: LocalizedStringResource? = nil,
        action: (() -> Void)? = nil
    ) {
        self.init(
            title: Text(title),
            message: message,
            systemImage: systemImage,
            style: style,
            actionTitle: actionTitle,
            action: action
        )
    }

    private init(
        title: Text,
        message: Text,
        systemImage: String,
        style: ColumnEmptyStateStyle,
        actionTitle: LocalizedStringResource?,
        action: (() -> Void)?
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.style = style
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        ColumnEmptyStateView(
            title: title,
            systemImage: systemImage,
            description: message,
            style: style
        ) {
            if let actionTitle, let action {
                Button(actionTitle, systemImage: "arrow.clockwise", action: action)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
