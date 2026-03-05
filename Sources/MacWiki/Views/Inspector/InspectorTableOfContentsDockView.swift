import SwiftUI
import AppKit

/// A compact, glassy "dock" for navigating the current article's Table of Contents.
///
/// In liquid mode this replaces the inline TOC list with a bottom tab that:
/// - updates as the reader scrolls (tracks the active section),
/// - expands on hover into a full live TOC list + controls.
struct InspectorTableOfContentsDockView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("inspectorTOCDockLockedOpen") private var isDockLockedOpen = false

    let items: [ArticleTableOfContentsItem]
    @Binding var presentation: InspectorTableOfContentsPresentation

    @State private var isHovered = false
    @State private var isPointerHoveringDock = false
    @State private var pulse = false
    @State private var expandWorkItem: DispatchWorkItem?
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var headerTransitionDirection: HeaderTransitionDirection = .down
    @State private var previousMajorSectionIndex: Int?

    private enum HeaderTransitionDirection {
        case up
        case down
    }

    private enum Metrics {
        static let cornerRadius: CGFloat = 16
        static let buttonSize: CGFloat = 26
        static let iconSize: CGFloat = 11
        static let collapsedMinWidth: CGFloat = 132
        static let collapsedMaxWidth: CGFloat = 250
        static let collapsedMinHeight: CGFloat = 34
        static let expandedMaxHeight: CGFloat = 270
        static let bottomStepperCornerRadius: CGFloat = 11
        static let lockedTitleMinHeight: CGFloat = 30
        static let bottomHoverInset: CGFloat = 14
        static let expandDelay: TimeInterval = 0.03
        static let collapseDelay: TimeInterval = 0.14
        static let lockedHeaderTitleTravel: CGFloat = 5
    }

    private var isExpanded: Bool {
        isHovered || isDockLockedOpen
    }

    private var activeItemIndex: Int? {
        guard let activeId = appState.currentVisibleTableOfContentsSectionId else { return nil }
        return items.firstIndex(where: { $0.id == activeId })
    }

    private var majorSectionItem: ArticleTableOfContentsItem? {
        guard let activeItemIndex else { return nil }
        // Prefer the closest preceding level-2 heading so the dock reads as "section"
        // rather than jittering through subheadings.
        if let major = items[...activeItemIndex].last(where: { $0.level == 2 }) {
            return major
        }
        return items[activeItemIndex]
    }

    private var majorSectionTitle: String {
        majorSectionItem?.title ?? "Contents"
    }

    private var collapsedTitle: String {
        let trimmed = majorSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Contents" : trimmed
    }

    private var majorSectionNavigationItems: [ArticleTableOfContentsItem] {
        let levelTwo = items.filter { $0.level == 2 }
        return levelTwo.isEmpty ? items : levelTwo
    }

    private var majorSectionActiveIndex: Int? {
        guard let majorId = majorSectionItem?.id else { return nil }
        return majorSectionNavigationItems.firstIndex(where: { $0.id == majorId })
    }

    private var previousMajorSection: ArticleTableOfContentsItem? {
        guard let majorSectionActiveIndex, majorSectionActiveIndex > 0 else { return nil }
        return majorSectionNavigationItems[majorSectionActiveIndex - 1]
    }

    private var nextMajorSection: ArticleTableOfContentsItem? {
        guard let majorSectionActiveIndex else {
            return majorSectionNavigationItems.first
        }
        let nextIndex = majorSectionActiveIndex + 1
        guard majorSectionNavigationItems.indices.contains(nextIndex) else { return nil }
        return majorSectionNavigationItems[nextIndex]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                dockContent
                    .frame(
                        minWidth: isExpanded ? 0 : Metrics.collapsedMinWidth,
                        maxWidth: isExpanded ? .infinity : Metrics.collapsedMaxWidth
                    )
                    .offset(y: isExpanded ? 0 : 1.2)
                Spacer(minLength: 0)
            }

            // Keep the visual bottom inset, but include it in hover hit-testing so
            // edge clicks don't thrash expand/collapse state.
            Color.clear
                .frame(height: Metrics.bottomHoverInset)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isPointerHoveringDock = hovering
            expandWorkItem?.cancel()
            expandWorkItem = nil
            collapseWorkItem?.cancel()
            collapseWorkItem = nil

            if hovering {
                scheduleExpandIfNeeded()
            } else {
                scheduleCollapseIfNeeded()
            }
        }
        .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, _ in
            guard !items.isEmpty else { return }
            // A tiny "alive" reaction so the dock feels like it's watching the reader.
            withAnimation(.easeOut(duration: 0.09)) {
                pulse = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.15)) {
                    pulse = false
                }
            }
        }
        .onChange(of: majorSectionActiveIndex) { oldValue, newValue in
            updateHeaderTransitionDirection(oldValue: oldValue, newValue: newValue)
        }
        .onAppear {
            previousMajorSectionIndex = majorSectionActiveIndex
        }
        .onDisappear {
            expandWorkItem?.cancel()
            expandWorkItem = nil
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        }
    }

    private func scheduleExpandIfNeeded() {
        let workItem = DispatchWorkItem {
            guard isPointerHoveringDock, !isHovered else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.96, blendDuration: 0.06)) {
                isHovered = true
            }
        }

        expandWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.expandDelay, execute: workItem)
    }

    private func scheduleCollapseIfNeeded() {
        let workItem = DispatchWorkItem {
            guard !isDockLockedOpen, !isPointerHoveringDock else { return }

            // Avoid hover-state thrash while a mouse-down drag/resize gesture is active.
            // Retry after the short delay once pointer activity settles.
            guard NSEvent.pressedMouseButtons == 0 else {
                scheduleCollapseIfNeeded()
                return
            }

            guard isHovered else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.98, blendDuration: 0.05)) {
                isHovered = false
            }
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.collapseDelay, execute: workItem)
    }

    private var dockContent: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 8 : 0) {
            headerRow

            if isExpanded {
                Divider()
                    .opacity(0.55)

                InspectorTableOfContentsInlineList(items: items) { id in
                    jump(to: id)
                }
                .frame(maxHeight: Metrics.expandedMaxHeight)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.995, anchor: .top)),
                        removal: .opacity
                    )
                )

                bottomSectionStepper
                    .padding(.top, 2)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity
                        )
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: isExpanded ? 0 : Metrics.collapsedMinHeight)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(colorScheme == .dark ? 0.10 : 0.025))
                }
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.09 : 0.10),
                            Color.white.opacity(colorScheme == .dark ? 0.016 : 0.02),
                            Color.black.opacity(colorScheme == .dark ? 0.07 : 0.018)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                    .blendMode(.screen)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.11 : 0.12),
                    lineWidth: 0.8
                )

            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1.1)
                .opacity(pulse ? 0.38 : 0)
        }
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.14 : 0.09),
            radius: 9,
            y: 4
        )
        .shadow(
            color: .black.opacity(colorScheme == .dark ? 0.055 : 0.04),
            radius: 3,
            y: 1
        )
        .scaleEffect(pulse ? 1.002 : 1)
        .animation(.spring(response: 0.21, dampingFraction: 0.93, blendDuration: 0.06), value: isExpanded)
    }

    private var headerRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.hierarchical)

            if isExpanded {
                expandedHeaderTitle
            } else {
                Text(collapsedTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }

            Spacer(minLength: 0)

            if isExpanded {
                Button {
                    isDockLockedOpen.toggle()
                } label: {
                    Image(systemName: isDockLockedOpen ? "lock.fill" : "lock.open")
                        .font(.system(size: Metrics.iconSize, weight: .semibold))
                        .foregroundStyle(isDockLockedOpen ? .primary : .secondary)
                        .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.accentColor.opacity(isDockLockedOpen ? 0.18 : 0))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.accentColor.opacity(isDockLockedOpen ? 0.32 : 0), lineWidth: 0.8)
                        )
                }
                .buttonStyle(.plain)
                .help(isDockLockedOpen ? "Unlock floating Contents" : "Lock floating Contents open")

                Divider()
                    .frame(height: 16)
                    .opacity(0.5)

                Button {
                    presentation = .standard
                } label: {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: Metrics.iconSize, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Metrics.buttonSize, height: Metrics.buttonSize)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .opacity(0.8)
            }
        }
        .frame(minHeight: 24)
    }

    private var bottomSectionStepper: some View {
        HStack(spacing: 0) {
            stepperButton(
                symbol: "chevron.up",
                enabled: previousMajorSection != nil,
                help: "Previous section"
            ) {
                if let previousMajorSection {
                    jump(to: previousMajorSection.id)
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.12))
                .frame(width: 0.6, height: 14)
                .padding(.horizontal, 2)

            stepperButton(
                symbol: "chevron.down",
                enabled: nextMajorSection != nil,
                help: "Next section"
            ) {
                if let nextMajorSection {
                    jump(to: nextMajorSection.id)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            RoundedRectangle(cornerRadius: Metrics.bottomStepperCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.bottomStepperCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.14), lineWidth: 0.6)
                )
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.20 : 0.08), radius: 2, y: 1)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.trailing, 1)
    }

    @ViewBuilder
    private func stepperButton(
        symbol: String,
        enabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(enabled ? .secondary : .tertiary)
                .frame(width: Metrics.buttonSize, height: Metrics.buttonSize - 2)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
    }

    private var expandedHeaderTitle: some View {
        ZStack(alignment: .leading) {
            Text(majorSectionTitle)
                .id(majorSectionTitle)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(isDockLockedOpen ? 2 : 3)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                .contentTransition(.interpolate)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: isDockLockedOpen ? Metrics.lockedTitleMinHeight : 0, alignment: .leading)
                .transition(expandedTitleTransition)
        }
        .animation(expandedTitleAnimation, value: majorSectionTitle)
    }

    private var expandedTitleTransition: AnyTransition {
        guard isDockLockedOpen else {
            return .opacity
        }

        let travel = Metrics.lockedHeaderTitleTravel
        switch headerTransitionDirection {
        case .down:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: travel)),
                removal: .opacity.combined(with: .offset(y: -travel * 0.8))
            )
        case .up:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: -travel)),
                removal: .opacity.combined(with: .offset(y: travel * 0.8))
            )
        }
    }

    private var expandedTitleAnimation: Animation {
        if isDockLockedOpen {
            return .interactiveSpring(response: 0.24, dampingFraction: 0.92, blendDuration: 0.06)
        }
        return .easeOut(duration: 0.14)
    }

    private func jump(to id: String) {
        appState.pendingTableOfContentsScrollTarget = id
        appState.currentVisibleTableOfContentsSectionId = id
    }

    private func updateHeaderTransitionDirection(oldValue: Int?, newValue: Int?) {
        guard let newValue else {
            previousMajorSectionIndex = nil
            return
        }

        let referenceIndex = oldValue ?? previousMajorSectionIndex
        if let referenceIndex {
            if newValue > referenceIndex {
                headerTransitionDirection = .down
            } else if newValue < referenceIndex {
                headerTransitionDirection = .up
            }
        }

        previousMajorSectionIndex = newValue
    }
}

private struct InspectorTableOfContentsInlineList: View {
    let items: [ArticleTableOfContentsItem]
    let onSelect: (String) -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        let isActive = appState.currentVisibleTableOfContentsSectionId == item.id
                        let indent = CGFloat(max(item.level - 2, 0)) * 14

                        Button {
                            onSelect(item.id)
                        } label: {
                            HStack(spacing: 6) {
                                if item.level > 2 {
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }

                                Text(item.title)
                                    .font(.caption)
                                    .fontWeight(isActive ? .medium : .regular)
                                    .foregroundStyle(isActive ? .primary : .secondary)
                                    .lineLimit(1)
                                    .contentTransition(.interpolate)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, indent)
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.accentColor.opacity(isActive ? 0.14 : 0))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Color.accentColor.opacity(0.28), lineWidth: 0.8)
                                    .opacity(isActive ? 1 : 0)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let active = appState.currentVisibleTableOfContentsSectionId,
                   let targetIndex = items.firstIndex(where: { $0.id == active }) {
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(targetIndex, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, newId in
                guard let newId else { return }
                guard let targetIndex = items.firstIndex(where: { $0.id == newId }) else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(targetIndex, anchor: .center)
                }
            }
        }
    }
}
