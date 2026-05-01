import SwiftUI

/// Shared centered empty state used by column surfaces (sidebar, inspector).
struct ColumnEmptyStateView: View {
    enum Style {
        case standard
        case quiet
    }

    let title: String
    let systemImage: String
    let description: String
    let style: Style

    init(
        title: String,
        systemImage: String,
        description: String,
        style: Style = .standard
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.style = style
    }

    var body: some View {
        VStack(spacing: style == .quiet ? 12 : 14) {
            if style == .quiet {
                Image(systemName: systemImage)
                    .font(.system(size: 40, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tertiary)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 36, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(0.06))
                    )
            }

            Text(title)
                .font(style == .quiet ? .headline : .system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text(description)
                .font(style == .quiet ? MacWikiTypography.settingsHelp : MacWikiTypography.emptyStateDescription)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, style == .quiet ? 20 : 22)
        .padding(.vertical, style == .quiet ? 16 : 20)
        .frame(maxWidth: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
