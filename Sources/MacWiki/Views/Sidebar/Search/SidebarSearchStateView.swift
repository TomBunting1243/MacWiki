import SwiftUI

struct SidebarSearchStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var style: ColumnEmptyStateView.Style = .standard

    var body: some View {
        ColumnEmptyStateView(
            title: title,
            systemImage: systemImage,
            description: message,
            style: style
        )
    }
}
