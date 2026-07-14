import SwiftUI

enum ColumnEmptyStateStyle {
    case standard
    case quiet

    fileprivate var maximumContentWidth: CGFloat {
        switch self {
        case .standard:
            360
        case .quiet:
            320
        }
    }
}

/// Native unavailable-state presentation shared by column surfaces.
struct ColumnEmptyStateView<Actions: View>: View {
    let title: Text
    let systemImage: String
    let description: Text
    let style: ColumnEmptyStateStyle
    let actions: Actions

    init(
        title: Text,
        systemImage: String,
        description: Text,
        style: ColumnEmptyStateStyle = .standard,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.style = style
        self.actions = actions()
    }

    var body: some View {
        ContentUnavailableView {
            SwiftUI.Label {
                title
            } icon: {
                Image(systemName: systemImage)
            }
        } description: {
            description
        } actions: {
            actions
        }
        .symbolRenderingMode(.hierarchical)
        .frame(maxWidth: style.maximumContentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

extension ColumnEmptyStateView where Actions == EmptyView {
    init(
        title: LocalizedStringResource,
        systemImage: String,
        description: LocalizedStringResource,
        style: ColumnEmptyStateStyle = .standard
    ) {
        self.init(
            title: Text(title),
            systemImage: systemImage,
            description: Text(description),
            style: style,
            actions: EmptyView.init
        )
    }
}
