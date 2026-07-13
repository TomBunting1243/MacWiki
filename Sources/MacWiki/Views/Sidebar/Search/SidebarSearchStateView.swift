import SwiftUI

struct SidebarSearchStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var style: ColumnEmptyStateView.Style = .standard
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ColumnEmptyStateView(
                title: title,
                systemImage: systemImage,
                description: message,
                style: style
            )

            if let actionTitle, let action {
                Button(actionTitle, systemImage: "arrow.clockwise", action: action)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, -10)
                    .padding(.bottom, 16)
            }
        }
    }
}
