import SwiftUI
import AppKit

struct ReaderFocusTOCView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false

    let items: [ArticleTableOfContentsItem]

    @State private var isHovered = false
    @State private var isPointerHoveringDock = false
    @State private var pulse = false
    @State private var expandWorkItem: DispatchWorkItem?
    @State private var collapseWorkItem: DispatchWorkItem?
    @State private var headerTransitionDirection: HeaderTransitionDirection = .down
    @State private var previousMajorSectionIndex: Int?
    @State private var expansionProgress: CGFloat = 0

    private enum HeaderTransitionDirection {
        case up
        case down
    }

    private enum Metrics {
        static let expandedWidth: CGFloat = 284
        static let collapsedWidth: CGFloat = 172
        static let cornerRadius: CGFloat = 14
        static let maxHeight: CGFloat = 420
        static let rowIndentStep: CGFloat = 14
        static let expandDelay: TimeInterval = 0.02
        static let collapseDelay: TimeInterval = 0.14
        static let headerTravel: CGFloat = 4
        static let pulseDuration: TimeInterval = 0.16
    }

    private var isExpanded: Bool {
        isHovered
    }

    private var activeItemIndex: Int? {
        guard let activeId = appState.currentVisibleTableOfContentsSectionId else { return nil }
        return items.firstIndex(where: { $0.id == activeId })
    }

    private var majorSectionItem: ArticleTableOfContentsItem? {
        guard let activeItemIndex else { return nil }
        if let major = items[...activeItemIndex].last(where: { $0.level == 2 }) {
            return major
        }
        return items[activeItemIndex]
    }

    private var majorSectionTitle: String {
        let raw = majorSectionItem?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? "Contents" : raw
    }

    private var collapsedSubtitle: String {
        if items.isEmpty {
            return "No headings"
        }
        if let majorSectionItem {
            let title = majorSectionItem.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return title
            }
        }
        let sectionLabel = items.count == 1 ? "section" : "sections"
        return "\(items.count) \(sectionLabel)"
    }

    private var clampedExpansionProgress: CGFloat {
        min(max(expansionProgress, 0), 1)
    }

    private var currentReadingProgress: Double {
        guard let title = appState.currentArticle?.title else { return 0 }
        return appState.liveReadingProgress(forTitle: title) ?? 0
    }

    private var clampedReadingProgress: Double {
        min(max(currentReadingProgress, 0), 1)
    }

    private var readingProgressLabel: String {
        "\(Int((clampedReadingProgress * 100).rounded()))%"
    }

    private var usesNativeGlass: Bool {
        tabBarLiquidGlass &&
            MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback)
    }

    private var resolvedWidth: CGFloat {
        interpolate(Metrics.collapsedWidth, Metrics.expandedWidth, progress: clampedExpansionProgress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 + (6 * clampedExpansionProgress)) {
            header
            if isExpanded || clampedExpansionProgress > 0.001 {
                Divider()
                    .opacity(0.52 * clampedExpansionProgress)
                listContent
                    .frame(maxHeight: Metrics.maxHeight)
                    .opacity(clampedExpansionProgress)
                    .offset(y: (1 - clampedExpansionProgress) * 8)
                    .scaleEffect(
                        x: 1,
                        y: 0.96 + (0.04 * clampedExpansionProgress),
                        anchor: .top
                    )
                    .allowsHitTesting(isExpanded)
            }
        }
        .padding(.horizontal, 10 + (2 * clampedExpansionProgress))
        .padding(.vertical, 8 + (4 * clampedExpansionProgress))
        .frame(width: resolvedWidth, alignment: .leading)
        .background {
            tocBackground
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.070 : 0.045), lineWidth: 0.55)

            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(colorScheme == .dark ? 0.16 : 0.12), lineWidth: 0.9)
                .opacity(pulse ? 1 : 0)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 10, y: 4)
        .scaleEffect(pulse ? 1.002 : 1)
        .contentShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .onHover { hovering in
            handleHoverChange(isHovering: hovering)
        }
        .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, _ in
            triggerSectionPulse()
        }
        .onChange(of: activeItemIndex) { oldValue, newValue in
            updateHeaderTransitionDirection(oldValue: oldValue, newValue: newValue)
        }
        .onAppear {
            previousMajorSectionIndex = activeItemIndex
            expansionProgress = isExpanded ? 1 : 0
        }
        .onDisappear {
            cancelHoverWorkItems()
        }
        .help(clampedExpansionProgress > 0.6 ? "Table of Contents" : "Hover to expand contents")
        .animation(
            reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.90, blendDuration: 0.08),
            value: clampedExpansionProgress
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.20),
            value: clampedReadingProgress
        )
    }

    @ViewBuilder
    private var tocBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
        if #available(macOS 26, *), usesNativeGlass {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cornerRadius))
                .overlay {
                    shape.fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.022 : 0.014)
                    )
                }
        } else {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(
                        Color(nsColor: .windowBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.10 : 0.06)
                    )
                }
        }
    }

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .leading) {
            collapsedHeader
                .opacity(1 - clampedExpansionProgress)
                .allowsHitTesting(clampedExpansionProgress < 0.20)

            expandedHeader
                .opacity(clampedExpansionProgress)
                .allowsHitTesting(clampedExpansionProgress > 0.80)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var collapsedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 0) {
                Text("Contents")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(collapsedSubtitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(readingProgressLabel)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(0.88)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: collapsedSubtitle
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.14),
            value: readingProgressLabel
        )
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            expandedHeaderTitle

            Spacer(minLength: 8)

            Button {
                appState.setFocusModeEnabled(false)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                    )
            }
            .buttonStyle(.plain)
            .help("Exit Focus Mode")
            .accessibilityLabel("Exit Focus Mode")
            .accessibilityHint("Restore the standard reading layout")
        }
    }

    private var expandedHeaderTitle: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack(alignment: .leading) {
                Text(majorSectionTitle)
                    .id(majorSectionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .contentTransition(.interpolate)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(expandedTitleTransition)
            }

            HStack(spacing: 6) {
                GeometryReader { proxy in
                    let progressWidth = max(0, proxy.size.width * clampedReadingProgress)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.20 : 0.10))

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.accentColor.opacity(colorScheme == .dark ? 0.85 : 0.75),
                                        Color.accentColor.opacity(colorScheme == .dark ? 0.60 : 0.52)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: progressWidth)
                    }
                }
                .frame(height: 4.5)

                Text(readingProgressLabel)
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .animation(expandedTitleAnimation, value: majorSectionTitle)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.16),
            value: clampedReadingProgress
        )
    }

    private var expandedTitleTransition: AnyTransition {
        guard !reduceMotion else { return .identity }

        switch headerTransitionDirection {
        case .down:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: Metrics.headerTravel)),
                removal: .opacity.combined(with: .offset(y: -Metrics.headerTravel * 0.8))
            )
        case .up:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: -Metrics.headerTravel)),
                removal: .opacity.combined(with: .offset(y: Metrics.headerTravel * 0.8))
            )
        }
    }

    private var expandedTitleAnimation: Animation? {
        reduceMotion
            ? nil
            : .interactiveSpring(response: 0.24, dampingFraction: 0.92, blendDuration: 0.06)
    }

    @ViewBuilder
    private var listContent: some View {
        if items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No section headings")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("This article does not expose a navigable table of contents. Press Esc to exit focus mode.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            let isActive = appState.currentVisibleTableOfContentsSectionId == item.id
                            let indent = CGFloat(max(item.level - 2, 0)) * Metrics.rowIndentStep

                            Button {
                                appState.pendingTableOfContentsScrollTarget = item.id
                                appState.currentVisibleTableOfContentsSectionId = item.id
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
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .contentTransition(.interpolate)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, indent)
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(
                                            isActive
                                                ? Color(nsColor: .windowBackgroundColor)
                                                    .opacity(colorScheme == .dark ? 0.16 : 0.09)
                                                : Color.clear
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .strokeBorder(
                                            Color.accentColor.opacity(colorScheme == .dark ? 0.14 : 0.10),
                                            lineWidth: 0.7
                                        )
                                        .opacity(isActive ? 1 : 0)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .animation(
                                reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.90),
                                value: isActive
                            )
                            .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
                .onAppear {
                    scrollToActiveSection(using: proxy, animated: false)
                }
                .onChange(of: appState.currentVisibleTableOfContentsSectionId) { _, _ in
                    scrollToActiveSection(using: proxy, animated: true)
                }
            }
        }
    }

    private func handleHoverChange(isHovering: Bool) {
        isPointerHoveringDock = isHovering
        cancelHoverWorkItems()

        if isHovering {
            scheduleExpandIfNeeded()
        } else {
            scheduleCollapseIfNeeded()
        }
    }

    private func scheduleExpandIfNeeded() {
        let workItem = DispatchWorkItem {
            guard isPointerHoveringDock, !isHovered else { return }
            performHoverAnimation(opening: true) {
                isHovered = true
                expansionProgress = 1
            }
        }

        expandWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.expandDelay, execute: workItem)
    }

    private func scheduleCollapseIfNeeded() {
        let workItem = DispatchWorkItem {
            guard !isPointerHoveringDock else { return }

            // Avoid hover thrash during click-drag interactions.
            guard NSEvent.pressedMouseButtons == 0 else {
                scheduleCollapseIfNeeded()
                return
            }

            guard isHovered else { return }
            performHoverAnimation(opening: false) {
                isHovered = false
                expansionProgress = 0
            }
        }

        collapseWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.collapseDelay, execute: workItem)
    }

    private func performHoverAnimation(opening: Bool, _ updates: () -> Void) {
        guard !reduceMotion else {
            updates()
            return
        }

        let animation: Animation = opening
            ? .spring(response: 0.20, dampingFraction: 0.89, blendDuration: 0.07)
            : .spring(response: 0.23, dampingFraction: 0.93, blendDuration: 0.07)
        withAnimation(animation, updates)
    }

    private func triggerSectionPulse() {
        guard !items.isEmpty else { return }
        guard !reduceMotion else { return }

        withAnimation(.easeOut(duration: 0.10)) {
            pulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.pulseDuration) {
            withAnimation(.easeOut(duration: 0.16)) {
                pulse = false
            }
        }
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

    private func interpolate(_ start: CGFloat, _ end: CGFloat, progress: CGFloat) -> CGFloat {
        let normalized = min(max(progress, 0), 1)
        return start + ((end - start) * normalized)
    }

    private func cancelHoverWorkItems() {
        expandWorkItem?.cancel()
        collapseWorkItem?.cancel()
        expandWorkItem = nil
        collapseWorkItem = nil
    }

    private func scrollToActiveSection(using proxy: ScrollViewProxy, animated: Bool) {
        guard let active = appState.currentVisibleTableOfContentsSectionId else { return }
        guard let targetIndex = items.firstIndex(where: { $0.id == active }) else { return }
        if animated && !reduceMotion {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(targetIndex, anchor: .center)
            }
            return
        }
        proxy.scrollTo(targetIndex, anchor: .center)
    }
}
