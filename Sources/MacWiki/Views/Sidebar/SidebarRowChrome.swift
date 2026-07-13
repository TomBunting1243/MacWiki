import AppKit
import SwiftUI

enum SidebarRowMetrics {
    static let horizontalInset: CGFloat = 8
    static let rowVerticalInset: CGFloat = 4
    static let rowBackgroundInset: CGFloat = -3
    static let rowSpacing: CGFloat = 8
    static let rowCornerRadius: CGFloat = 7
    static let leadingSlotWidth: CGFloat = 18
    static let trailingCountWidth: CGFloat = 24
    static let headerAccessorySize: CGFloat = 24
    static let headerMinHeight: CGFloat = 34
    static let nativeTopContentInset: CGFloat = 44
    static let titlebarContentPadding: CGFloat = 10
    static let bodyFont: Font = .system(size: 13)
    static let symbolFont: Font = .system(size: 15, weight: .regular)
    static let countFont: Font = .system(size: 11)
    static let sectionHeaderFont: Font = .system(size: 13, weight: .semibold)
    static let labelDotSize: CGFloat = 8
    static let microInteractionDuration: Double = 0.15
}

enum SidebarRowSelectionVisuals {
    static let tint = Color(red: 0.22, green: 0.50, blue: 0.88)

    static func primaryForeground(isSelected: Bool, isHighlighted: Bool = false) -> Color {
        if isHighlighted {
            return tint
        }
        return isSelected ? tint : .primary
    }
}

struct SidebarRowLayoutMetrics: Equatable {
    let horizontalInset: CGFloat
    let rowBackgroundInset: CGFloat
    let rowSpacing: CGFloat

    static let regular = SidebarRowLayoutMetrics(
        horizontalInset: SidebarRowMetrics.horizontalInset,
        rowBackgroundInset: SidebarRowMetrics.rowBackgroundInset,
        rowSpacing: SidebarRowMetrics.rowSpacing
    )

    init(horizontalInset: CGFloat, rowBackgroundInset: CGFloat, rowSpacing: CGFloat) {
        self.horizontalInset = horizontalInset
        self.rowBackgroundInset = rowBackgroundInset
        self.rowSpacing = rowSpacing
    }

    init(availableWidth: CGFloat) {
        guard availableWidth > 0 else {
            self = .regular
            return
        }

        if availableWidth < 196 {
            self.init(horizontalInset: 6, rowBackgroundInset: -2, rowSpacing: 7)
        } else if availableWidth < 224 {
            self.init(horizontalInset: 7, rowBackgroundInset: -2, rowSpacing: 8)
        } else {
            self = .regular
        }
    }
}

private struct SidebarRowLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = SidebarRowLayoutMetrics.regular
}

private struct SidebarRowSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sidebarRowLayoutMetrics: SidebarRowLayoutMetrics {
        get { self[SidebarRowLayoutMetricsKey.self] }
        set { self[SidebarRowLayoutMetricsKey.self] = newValue }
    }

    var sidebarRowIsSelected: Bool {
        get { self[SidebarRowSelectedKey.self] }
        set { self[SidebarRowSelectedKey.self] = newValue }
    }
}

private struct SidebarListRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

struct SidebarRowContainer<Content: View>: View {
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics

    let isSelected: Bool
    let content: Content

    @State private var isHovered = false

    init(
        isSelected: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.isSelected = isSelected
        self.content = content()
    }

    private var isKeyWindow: Bool {
        controlActiveState == .key
    }

    private var selectedFill: Color {
        if colorScheme == .dark {
            return SidebarRowSelectionVisuals.tint.opacity(isKeyWindow ? 0.18 : 0.11)
        }
        return SidebarRowSelectionVisuals.tint.opacity(isKeyWindow ? 0.12 : 0.08)
    }

    private var hoverFill: Color {
        if colorScheme == .dark {
            return Color.white.opacity(isKeyWindow ? 0.070 : 0.048)
        }
        return Color.black.opacity(isKeyWindow ? 0.042 : 0.028)
    }

    private var selectedStroke: Color {
        if colorScheme == .dark {
            return SidebarRowSelectionVisuals.tint.opacity(isHovered ? 0.28 : 0.18)
        }
        return SidebarRowSelectionVisuals.tint.opacity(isHovered ? 0.24 : 0.15)
    }

    private var hoverStroke: Color {
        if colorScheme == .dark {
            return Color.white.opacity(0.10)
        }
        return Color.black.opacity(0.055)
    }

    private var fillColor: Color {
        if isSelected {
            return selectedFill
        }
        if isHovered {
            return hoverFill
        }
        return .clear
    }

    private var strokeColor: Color {
        if isSelected {
            return selectedStroke
        }
        if isHovered {
            return hoverStroke
        }
        return .clear
    }

    private var strokeLineWidth: CGFloat {
        isSelected ? 0.5 : 0
    }

    var body: some View {
        content
            .environment(\.sidebarRowIsSelected, isSelected)
            .foregroundStyle(
                isSelected
                    ? AnyShapeStyle(SidebarRowSelectionVisuals.tint)
                    : AnyShapeStyle(.primary)
            )
            .font(SidebarRowMetrics.bodyFont)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, layoutMetrics.horizontalInset)
            .padding(.vertical, SidebarRowMetrics.rowVerticalInset)
            .background {
                RoundedRectangle(cornerRadius: SidebarRowMetrics.rowCornerRadius, style: .continuous)
                    .fill(fillColor)
                    .overlay {
                        RoundedRectangle(cornerRadius: SidebarRowMetrics.rowCornerRadius, style: .continuous)
                            .strokeBorder(strokeColor, lineWidth: strokeLineWidth)
                    }
                    .padding(.horizontal, layoutMetrics.rowBackgroundInset)
            }
            .contentShape(Rectangle())
            .modifier(SidebarListRowModifier())
            .animation(
                reduceMotion ? nil : .easeOut(duration: SidebarRowMetrics.microInteractionDuration),
                value: isHovered
            )
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
            }
    }
}

struct SidebarLeadingSlot<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: SidebarRowMetrics.leadingSlotWidth, alignment: .center)
    }
}

struct SidebarSymbolIcon: View {
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(SidebarRowMetrics.symbolFont)
            .foregroundStyle(SidebarRowSelectionVisuals.primaryForeground(isSelected: isSelected))
            .frame(width: SidebarRowMetrics.leadingSlotWidth, alignment: .center)
    }
}

struct SidebarCountBadge: View {
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(SidebarRowMetrics.countFont)
            .foregroundStyle(isSelected ? SidebarRowSelectionVisuals.tint.opacity(0.72) : .secondary)
            .monospacedDigit()
            .frame(width: SidebarRowMetrics.trailingCountWidth, alignment: .trailing)
    }
}
