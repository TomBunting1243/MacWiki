import SwiftUI
import SwiftData

enum TabBarChromeStyle {
    case standalone
    case titlebarAccessory
    case strip

    var isCompactChrome: Bool {
        switch self {
        case .standalone:
            return false
        case .titlebarAccessory, .strip:
            return true
        }
    }

    var height: CGFloat {
        switch self {
        case .standalone: return 52
        case .titlebarAccessory: return 34
        case .strip: return 32
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .standalone: return 16
        case .titlebarAccessory: return 10
        case .strip: return 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .standalone: return 10
        case .titlebarAccessory: return 3
        case .strip: return 2
        }
    }

    var tabMaxWidth: CGFloat {
        switch self {
        case .standalone: return 240
        case .titlebarAccessory: return 240
        case .strip: return 240
        }
    }

    var tabMinWidth: CGFloat {
        switch self {
        case .standalone: return 160
        case .titlebarAccessory: return 128
        case .strip: return 120
        }
    }

    var newTabButtonSize: CGFloat {
        switch self {
        case .standalone: return 32
        case .titlebarAccessory: return 28
        case .strip: return 24
        }
    }
}

private enum TabChromeHierarchy {
    static func titleActiveOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.98 : 0.96
    }

    static func titleHoverOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.92 : 0.90
    }

    static func titleInactiveOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.84 : 0.82
    }

    static func iconPrimaryOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.62 : 0.56
    }

    static func progressTrackOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.09 : 0.07
    }

    static func progressFillOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.54 : 0.46
    }

    static func activeLiftYOffset() -> CGFloat {
        -0.12
    }

    static func activeShadowOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.05 : 0.025
    }

    static func activeShadowRadius() -> CGFloat {
        0.8
    }

    static func activeShadowYOffset() -> CGFloat {
        0.35
    }

    static func activeGlassTintOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.010 : 0.008
    }

    static func nativeAccessoryTintOpacity(darkMode: Bool, compactAccessory: Bool) -> Double {
        if darkMode {
            return compactAccessory ? 0.16 : 0.18
        }
        return compactAccessory ? 0.42 : 0.48
    }

    static func nativeAccessoryStrokeOpacity(darkMode: Bool, compactAccessory: Bool) -> Double {
        if darkMode {
            return compactAccessory ? 0.074 : 0.082
        }
        return compactAccessory ? 0.056 : 0.064
    }
}

/// Horizontal scrollable tab bar for managing open articles
struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(TabAccompanimentStorageKey.showSavedMarker) private var showSavedTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showHighlightMarker) private var showHighlightTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showReadMarker) private var showReadTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showProgressTrack) private var showTabProgressTrack = true
    @AppStorage(TabAccompanimentStorageKey.showActiveDepth) private var showTabActiveDepth = true
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Highlight.updatedAt, order: .reverse) private var highlights: [Highlight]
    let chromeStyle: TabBarChromeStyle
    let showsTopDivider: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void
    
    // MARK: - Drag State
    @State private var draggedTabId: UUID?
    @State private var draggedSourceIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    @State private var tabFrames: [UUID: CGRect] = [:]
    
    // MARK: - Performance: Memoized target position
    /// Only changes when drag crosses a tab boundary, not every pixel
    @State private var currentTargetIndex: Int = 0

    // MARK: - Overflow + Scroll
    @State private var tabsContentWidth: CGFloat = 0
    @State private var tabsViewportWidth: CGFloat = 0
    @State private var tabsViewportFrame: CGRect = .zero
    @State private var pendingScrollTabId: UUID?
    @State private var lastDragAutoScrollTimestamp: TimeInterval = 0
    
    private var showsOverflowMenu: Bool {
        tabsContentWidth > (tabsViewportWidth + 30)
    }

    private var savedArticleTitleSet: Set<String> {
        Set(
            lists.flatMap { list in
                list.articles.map { ReadStateSync.normalizedTitle($0.title) }
            }
        )
    }

    private var highlightedArticleTitleSet: Set<String> {
        Set(
            highlights
                .lazy
                .filter { !$0.isArchived }
                .map { ReadStateSync.normalizedTitle($0.articleTitle) }
        )
    }

    private var interactionProfile: TabInteractionProfile {
        TabInteractionProfile.resolve(
            for: tabsViewportWidth,
            chromeStyle: chromeStyle,
            reduceMotion: reduceMotion
        )
    }

    private var tabSpacing: CGFloat {
        if chromeStyle == .standalone {
            return 8
        }
        if chromeStyle == .strip {
            return 4
        }
        return interactionProfile.tabSpacing
    }

    private var stripAccessoryCornerRadius: CGFloat {
        TopChromeControlMetrics.accessoryCornerRadius(compact: chromeStyle == .strip)
    }

    private var resolvedTabWidth: CGFloat {
        if chromeStyle == .standalone {
            return chromeStyle.tabMaxWidth
        }

        let viewport = tabsViewportWidth > 0 ? tabsViewportWidth : (chromeStyle == .strip ? 900 : 720)
        let buttonReserve = (chromeStyle == .strip ? chromeStyle.newTabButtonSize + 8 : chromeStyle.newTabButtonSize + 14)
            + (showsOverflowMenu ? (chromeStyle == .strip ? chromeStyle.newTabButtonSize + 8 : chromeStyle.newTabButtonSize + 12) : 0)
        let available = max(200, viewport - buttonReserve)

        if chromeStyle.isCompactChrome {
            // Proportional sizing: each tab gets an equal share, clamped to min/max.
            let tabCount = max(1, appState.openTabs.count)
            let totalSpacing = tabSpacing * CGFloat(max(0, tabCount - 1))
            let proportional = (available - totalSpacing) / CGFloat(tabCount)
            return min(max(proportional, chromeStyle.tabMinWidth), chromeStyle.tabMaxWidth)
        }

        // .standalone: original preferredVisibleTabCount-based sizing
        let desiredVisibleTabCount = max(
            1,
            min(appState.openTabs.count, interactionProfile.preferredVisibleTabCount)
        )
        let totalSpacing = tabSpacing * CGFloat(max(0, desiredVisibleTabCount - 1))
        let candidate = max(70, (available - totalSpacing) / CGFloat(desiredVisibleTabCount))
        return min(max(candidate, interactionProfile.tabMinWidth), chromeStyle.tabMaxWidth)
    }

    init(
        chromeStyle: TabBarChromeStyle = .standalone,
        showsTopDivider: Bool = true,
        onNewLabelWithArticle: @escaping (SavedArticle) -> Void
    ) {
        self.chromeStyle = chromeStyle
        self.showsTopDivider = showsTopDivider
        self.onNewLabelWithArticle = onNewLabelWithArticle
    }

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }
    
    var body: some View {
        let savedTitles = savedArticleTitleSet
        let highlightedTitles = highlightedArticleTitleSet

        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    MacWikiGlassGroup(spacing: tabSpacing) {
                        HStack(spacing: tabSpacing) {
                            ForEach(Array(appState.openTabs.enumerated()), id: \.element.id) { index, tab in
                                DraggableTabItemView(
                                    tab: tab,
                                    tabIndex: index,
                                    lists: lists,
                                    allLabels: allLabels,
                                    liquidGlassChrome: liquidGlassChrome,
                                    isActive: appState.activeTabId == tab.id,
                                    isDragged: draggedTabId == tab.id,
                                    dragOffset: draggedTabId == tab.id ? dragOffset : 0,
                                    shiftAmount: shiftAmount(for: index),
                                    chromeStyle: chromeStyle,
                                    tabWidth: resolvedTabWidth,
                                    interactionProfile: interactionProfile,
                                    isSaved: isSaved(tab, savedTitles: savedTitles),
                                    hasHighlights: hasHighlights(tab, highlightedTitles: highlightedTitles),
                                    readingProgress: readingProgress(for: tab),
                                    showSavedMarker: showSavedTabMarker,
                                    showHighlightMarker: showHighlightTabMarker,
                                    showReadMarker: showReadTabMarker,
                                    showProgressTrack: showTabProgressTrack,
                                    showActiveDepth: showTabActiveDepth,
                                    reduceMotion: reduceMotion,
                                    onNewLabelWithArticle: onNewLabelWithArticle,
                                    onClose: {
                                        performAnimation(interactionProfile.tabCreateClose) {
                                            appState.closeTab(tab.id)
                                        }
                                    },
                                    onSelect: {
                                        performAnimation(interactionProfile.tabSelect) {
                                            appState.activeTabId = tab.id
                                        }
                                        appState.flushSaveNow()
                                    },
                                    onDragChanged: { translation, locationX in
                                        handleDragChanged(tab: tab, at: index, translation: translation, dragLocationX: locationX)
                                    },
                                    onDragEnded: {
                                        finalizeDrag(at: index)
                                    }
                                )
                                .id(tab.id)
                            }
                        }
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(key: TabContentWidthPreferenceKey.self, value: geo.size.width)
                            }
                        )
                    }
                    .coordinateSpace(name: "TabBarSpace")
                    .onPreferenceChange(TabFramePreferenceKey.self) { frames in
                        guard frames != tabFrames else { return }
                        tabFrames = frames
                    }
                }
                .scrollIndicators(.hidden)
                .scrollDisabled(draggedTabId != nil)
                .scrollClipDisabled(false)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                updateTabsViewportWidth(geo.size.width)
                                updateTabsViewportFrame(geo.frame(in: .named("TabBarSpace")))
                            }
                            .onChange(of: geo.size.width) { _, newWidth in
                                updateTabsViewportWidth(newWidth)
                            }
                            .onChange(of: geo.frame(in: .named("TabBarSpace"))) { _, newFrame in
                                updateTabsViewportFrame(newFrame)
                            }
                    }
                )
                .onPreferenceChange(TabContentWidthPreferenceKey.self) { width in
                    guard abs(tabsContentWidth - width) > 0.5 else { return }
                    tabsContentWidth = width
                }
                .onAppear {
                    scrollToActiveTab(with: proxy, animated: false)
                }
                .onChange(of: appState.activeTabId) { _, _ in
                    scrollToActiveTab(with: proxy, animated: true)
                }
                .onChange(of: appState.openTabs.map(\.id)) { _, _ in
                    scrollToActiveTab(with: proxy, animated: true)
                }
                .onChange(of: pendingScrollTabId) { _, tabId in
                    guard let tabId else { return }
                    performAnimation(interactionProfile.dragAutoScroll) {
                        proxy.scrollTo(tabId, anchor: .center)
                    }
                    pendingScrollTabId = nil
                }
            }
            .frame(maxWidth: .infinity) // Force logical expansion for sizing

            trailingAccessoryCluster
        }
        .padding(.horizontal, chromeStyle.horizontalPadding)
        .padding(.vertical, chromeStyle.verticalPadding)
        .frame(height: chromeStyle.height)
        .background(tabBarBackground)
        .overlay(alignment: .top) {
            if chromeStyle == .standalone {
                Divider().opacity(0.5)
            }
        }
        .overlay(alignment: .bottom) {
            if chromeStyle == .standalone {
                Divider().opacity(0.5)
            }
        }
        .animation(interactionProfile.overflowAffordance, value: showsOverflowMenu)
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        if chromeStyle == .strip {
            ReaderTabLaneBackground()
                .overlay(alignment: .top) {
                    if showsTopDivider {
                        Rectangle()
                            .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                            .frame(height: 0.5)
                    }
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                        .frame(height: 0.5)
                }
        } else if chromeStyle == .titlebarAccessory {
            ReaderTabLaneBackground()
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                        .frame(height: 0.5)
                }
        } else if chromeStyle == .standalone {
            if liquidGlassChrome {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(colorScheme == .dark ? 0.24 : 0.14)
                    }
            }
        }
    }

    @ViewBuilder
    private func stripAccessoryBackground() -> some View {
        let darkMode = colorScheme == .dark
        if chromeStyle.isCompactChrome {
            let cornerRadius = stripAccessoryCornerRadius
            let compactAccessory = chromeStyle == .strip
            if #available(macOS 26, *), usesNativeGlassAccessories {
                nativeStripAccessoryBackground(cornerRadius: cornerRadius)
            } else if liquidGlassChrome {
                let fillOpacity = darkMode
                    ? (compactAccessory ? 0.14 : 0.16)
                    : (compactAccessory ? 0.085 : 0.10)
                let edgeOpacity = darkMode
                    ? (compactAccessory ? 0.052 : 0.060)
                    : (compactAccessory ? 0.044 : 0.052)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(fillOpacity))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.primary.opacity(edgeOpacity), lineWidth: 0.44)
                    }
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.68 : 0.82))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(darkMode ? 0.08 : 0.06),
                                lineWidth: 0.50
                            )
                    )
            }
        } else if liquidGlassChrome {
            Circle()
                .fill(.thinMaterial)
                .overlay(
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.22 : 0.14))
                )
                .overlay(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.22),
                                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.04)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .blendMode(.screen)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.30), lineWidth: 0.8)
                )
                .overlay(
                    Circle()
                        .strokeBorder(Color.black.opacity(colorScheme == .dark ? 0.24 : 0.10), lineWidth: 0.6)
                        .blendMode(.multiply)
                )
        } else {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.22 : 0.10), lineWidth: 0.7)
                )
        }
    }

    private var overflowMenu: some View {
        Menu {
            ForEach(appState.openTabs) { tab in
                Button {
                    performAnimation(interactionProfile.tabSelect) {
                        appState.activeTabId = tab.id
                    }
                } label: {
                    SwiftUI.Label {
                        Text(tab.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: appState.activeTabId == tab.id ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        } label: {
            stripAccessoryLabel(
                systemImage: chromeStyle.isCompactChrome ? "chevron.down" : "chevron.down.circle",
                imageScale: .small
            )
        }
        .menuStyle(.borderlessButton)
        .help("All Tabs")
        .accessibilityHint("Shows open tabs")
    }

    private var trailingAccessoryCluster: some View {
        MacWikiGlassGroup(spacing: 8) {
            HStack(spacing: 8) {
                if showsOverflowMenu {
                    overflowMenu
                }

                Button {
                    performAnimation(interactionProfile.tabCreateClose) {
                        appState.createNewTab()
                    }
                } label: {
                    stripAccessoryLabel(systemImage: "plus", imageScale: .medium)
                }
                .buttonStyle(.plain)
                .help("New Tab (⌘T)")
                .accessibilityLabel("New Tab")
                .accessibilityHint("Creates a new tab")
            }
        }
    }

    @ViewBuilder
    private func stripAccessoryLabel(systemImage: String, imageScale: Image.Scale) -> some View {
        if chromeStyle.isCompactChrome {
            Image(systemName: systemImage)
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(imageScale)
                .foregroundStyle(
                    Color.primary.opacity(
                        TabChromeHierarchy.iconPrimaryOpacity(darkMode: colorScheme == .dark)
                    )
                )
                .frame(
                    width: chromeStyle == .strip ? ChromeIconMetrics.compactButtonSize : ChromeIconMetrics.buttonSize,
                    height: chromeStyle == .strip ? ChromeIconMetrics.compactButtonSize : ChromeIconMetrics.buttonSize
                )
                .background(stripAccessoryBackground())
                .contentShape(RoundedRectangle(cornerRadius: stripAccessoryCornerRadius, style: .continuous))
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: chromeStyle.newTabButtonSize, height: chromeStyle.newTabButtonSize)
                .background(stripAccessoryBackground())
                .contentShape(Circle())
        }
    }

    private var usesNativeGlassAccessories: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        ) && chromeStyle.isCompactChrome
    }

    @available(macOS 26, *)
    private func nativeStripAccessoryBackground(cornerRadius: CGFloat) -> some View {
        let compactAccessory = chromeStyle == .strip
        let darkMode = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return shape
            .fill(.thinMaterial)
            .overlay {
                shape
                    .fill(
                        Color(nsColor: .controlBackgroundColor)
                            .opacity(
                                TabChromeHierarchy.nativeAccessoryTintOpacity(
                                    darkMode: darkMode,
                                    compactAccessory: compactAccessory
                                )
                            )
                    )
            }
            .overlay {
                shape
                    .strokeBorder(
                        Color.primary.opacity(
                            TabChromeHierarchy.nativeAccessoryStrokeOpacity(
                                darkMode: darkMode,
                                compactAccessory: compactAccessory
                            )
                        ),
                        lineWidth: 0.5
                    )
            }
    }
    
    // MARK: - Drag Calculations (Optimized)

    private func scrollToActiveTab(with proxy: ScrollViewProxy, animated: Bool) {
        guard let activeTabId = appState.activeTabId else { return }
        if animated {
            performAnimation(interactionProfile.tabSelect) {
                proxy.scrollTo(activeTabId, anchor: .center)
            }
        } else {
            proxy.scrollTo(activeTabId, anchor: .center)
        }
    }
    
    /// Handle drag changes with memoized target calculation
    private func handleDragChanged(tab: ArticleTab, at index: Int, translation: CGFloat, dragLocationX: CGFloat) {
        // Initialize drag if just starting
        if draggedTabId == nil {
            draggedTabId = tab.id
            draggedSourceIndex = index
            currentTargetIndex = index
        }
        
        // Always update the visual offset (GPU-cheap)
        dragOffset = translation
        
        // Calculate new target position based on actual tab frames
        let dragOriginX = tabFrames[tab.id]?.midX ?? dragLocationX
        let projectedMidX = dragOriginX + translation
        let newTarget = targetIndex(for: projectedMidX, fallback: currentTargetIndex)
        maybeAutoScrollDuringDrag(pointerX: dragLocationX)
        
        // Only trigger neighbor animations when target actually changes
        if newTarget != currentTargetIndex {
            triggerReorderHaptic()
            performAnimation(interactionProfile.neighborShift) {
                currentTargetIndex = newTarget
            }
        }
    }
    
    /// O(1) shift calculation using memoized target index
    private func shiftAmount(for index: Int) -> CGFloat {
        TabBarDragPlanner.shiftAmount(
            for: index,
            draggedTabID: draggedTabId,
            draggedSourceIndex: draggedSourceIndex,
            currentTargetIndex: currentTargetIndex,
            tabFrames: tabFrames,
            tabSpacing: tabSpacing
        )
    }
    
    /// Finalize the drag operation
    private func finalizeDrag(at sourceIndex: Int) {
        let targetIndex = currentTargetIndex
        
        // Perform the actual move if needed
        // Use draggedSourceIndex (set when drag started) rather than sourceIndex parameter,
        // which may become stale if the ForEach re-renders during the drag gesture.
        if targetIndex != draggedSourceIndex {
            performAnimation(interactionProfile.neighborShift) {
                appState.moveTab(from: draggedSourceIndex, to: targetIndex)
            }
        }
        
        // Reset drag state after move to avoid visual snap-back jitter
        performAnimation(interactionProfile.snapBack) {
            dragOffset = 0
            draggedTabId = nil
            currentTargetIndex = 0
            pendingScrollTabId = nil
        }
    }

    private func targetIndex(for pointerX: CGFloat, fallback: Int) -> Int {
        TabBarDragPlanner.targetIndex(
            pointerX: pointerX,
            currentTargetIndex: currentTargetIndex,
            tabOrder: appState.openTabs.map(\.id),
            tabFrames: tabFrames,
            fallback: fallback
        )
    }

    private func maybeAutoScrollDuringDrag(pointerX: CGFloat) {
        let now = Date().timeIntervalSince1970
        if now - lastDragAutoScrollTimestamp < interactionProfile.dragAutoScrollThrottle {
            return
        }

        guard let index = TabBarDragPlanner.autoScrollTargetIndex(
            pointerX: pointerX,
            viewportFrame: tabsViewportFrame,
            viewportWidth: tabsViewportWidth,
            contentWidth: tabsContentWidth,
            currentTargetIndex: currentTargetIndex,
            tabCount: appState.openTabs.count,
            edgeThreshold: interactionProfile.dragEdgeThreshold
        ),
        appState.openTabs.indices.contains(index) else {
            return
        }

        let targetId = appState.openTabs[index].id
        guard pendingScrollTabId != targetId else { return }
        pendingScrollTabId = targetId
        lastDragAutoScrollTimestamp = now
    }

    private func triggerReorderHaptic() {
        // SwiftUI owns the interaction now; keep reorder motion visual-only until a
        // view-scoped sensoryFeedback trigger is introduced for this drag path.
    }

    private func updateTabsViewportWidth(_ newWidth: CGFloat) {
        guard abs(tabsViewportWidth - newWidth) > 0.5 else { return }
        tabsViewportWidth = newWidth
    }

    private func updateTabsViewportFrame(_ newFrame: CGRect) {
        guard
            abs(tabsViewportFrame.minX - newFrame.minX) > 0.5 ||
            abs(tabsViewportFrame.minY - newFrame.minY) > 0.5 ||
            abs(tabsViewportFrame.width - newFrame.width) > 0.5 ||
            abs(tabsViewportFrame.height - newFrame.height) > 0.5
        else {
            return
        }
        tabsViewportFrame = newFrame
    }

    private func normalizedTitle(for tab: ArticleTab) -> String {
        ReadStateSync.normalizedTitle(tab.title)
    }

    private func isSaved(_ tab: ArticleTab, savedTitles: Set<String>) -> Bool {
        guard !tab.isPlaceholder else { return false }
        return savedTitles.contains(normalizedTitle(for: tab))
    }

    private func hasHighlights(_ tab: ArticleTab, highlightedTitles: Set<String>) -> Bool {
        guard !tab.isPlaceholder else { return false }
        return highlightedTitles.contains(normalizedTitle(for: tab))
    }

    private func readingProgress(for tab: ArticleTab) -> Double {
        guard let article = tab.currentArticle else { return 0 }
        if article.isRead {
            return 1
        }
        let normalized = normalizedTitle(for: tab)
        let liveProgress = appState.liveReadingProgressByTitle[normalized] ?? 0
        return min(max(liveProgress, 0), 1)
    }
}

private struct TabInteractionProfile {
    let tabSelect: Animation?
    let tabCreateClose: Animation?
    let neighborShift: Animation?
    let snapBack: Animation?
    let dragLift: Animation?
    let hover: Animation?
    let closeButtonShow: Animation?
    let closeButtonHide: Animation?
    let overflowAffordance: Animation?
    let dragAutoScroll: Animation?
    let dragAutoScrollThrottle: TimeInterval
    let dragEdgeThreshold: CGFloat
    let dragStartDistance: CGFloat
    let tabMinWidth: CGFloat
    let preferredVisibleTabCount: Int
    let tabSpacing: CGFloat

    static func resolve(
        for viewportWidth: CGFloat,
        chromeStyle: TabBarChromeStyle,
        reduceMotion: Bool
    ) -> TabInteractionProfile {
        let fallbackWidth: CGFloat = chromeStyle.isCompactChrome ? 720 : 900
        let width = viewportWidth > 0 ? viewportWidth : fallbackWidth
        let isStrip = chromeStyle.isCompactChrome
        let density = TopChromeMotion.Density.resolve(for: width)

        if reduceMotion {
            switch density {
            case .compact:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.045,
                    dragEdgeThreshold: 34,
                    dragStartDistance: 4,
                    tabMinWidth: 110,
                    preferredVisibleTabCount: 6,
                    tabSpacing: 7
                )
            case .regular:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.05,
                    dragEdgeThreshold: 42,
                    dragStartDistance: 4,
                    tabMinWidth: 120,
                    preferredVisibleTabCount: 5,
                    tabSpacing: 8
                )
            case .spacious:
                return TabInteractionProfile(
                    tabSelect: nil,
                    tabCreateClose: nil,
                    neighborShift: nil,
                    snapBack: nil,
                    dragLift: nil,
                    hover: nil,
                    closeButtonShow: nil,
                    closeButtonHide: nil,
                    overflowAffordance: nil,
                    dragAutoScroll: nil,
                    dragAutoScrollThrottle: 0.06,
                    dragEdgeThreshold: 50,
                    dragStartDistance: 5,
                    tabMinWidth: 140,
                    preferredVisibleTabCount: 5,
                    tabSpacing: 9
                )
            }
        }

        switch density {
        case .compact:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density, strip: isStrip),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density, strip: isStrip),
                neighborShift: TopChromeMotion.neighborShift(density: density, strip: isStrip),
                snapBack: TopChromeMotion.snapBack(density: density, strip: isStrip),
                dragLift: TopChromeMotion.dragLift(density: density, strip: isStrip),
                hover: TopChromeMotion.hover(density: density, strip: isStrip),
                closeButtonShow: TopChromeMotion.closeReveal(density: density, strip: isStrip),
                closeButtonHide: TopChromeMotion.closeHide(density: density, strip: isStrip),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density, strip: isStrip),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.045,
                dragEdgeThreshold: 34,
                dragStartDistance: 4,
                tabMinWidth: 110,
                preferredVisibleTabCount: 6,
                tabSpacing: 7
            )
        case .regular:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density, strip: isStrip),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density, strip: isStrip),
                neighborShift: TopChromeMotion.neighborShift(density: density, strip: isStrip),
                snapBack: TopChromeMotion.snapBack(density: density, strip: isStrip),
                dragLift: TopChromeMotion.dragLift(density: density, strip: isStrip),
                hover: TopChromeMotion.hover(density: density, strip: isStrip),
                closeButtonShow: TopChromeMotion.closeReveal(density: density, strip: isStrip),
                closeButtonHide: TopChromeMotion.closeHide(density: density, strip: isStrip),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density, strip: isStrip),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.05,
                dragEdgeThreshold: 42,
                dragStartDistance: 4,
                tabMinWidth: 120,
                preferredVisibleTabCount: 5,
                tabSpacing: 8
            )
        case .spacious:
            return TabInteractionProfile(
                tabSelect: TopChromeMotion.tabSelect(density: density, strip: isStrip),
                tabCreateClose: TopChromeMotion.tabCreateClose(density: density, strip: isStrip),
                neighborShift: TopChromeMotion.neighborShift(density: density, strip: isStrip),
                snapBack: TopChromeMotion.snapBack(density: density, strip: isStrip),
                dragLift: TopChromeMotion.dragLift(density: density, strip: isStrip),
                hover: TopChromeMotion.hover(density: density, strip: isStrip),
                closeButtonShow: TopChromeMotion.closeReveal(density: density, strip: isStrip),
                closeButtonHide: TopChromeMotion.closeHide(density: density, strip: isStrip),
                overflowAffordance: TopChromeMotion.overflowAffordance(density: density, strip: isStrip),
                dragAutoScroll: TopChromeMotion.dragAutoScroll(density: density),
                dragAutoScrollThrottle: 0.06,
                dragEdgeThreshold: 50,
                dragStartDistance: 5,
                tabMinWidth: 140,
                preferredVisibleTabCount: 5,
                tabSpacing: 9
            )
        }
    }
}

enum TabAccessibilityStatus {
    static func value(
        isActive: Bool,
        isSaved: Bool,
        hasHighlights: Bool,
        isRead: Bool,
        showsProgress: Bool,
        progress: Double
    ) -> String {
        var parts: [String] = [isActive ? "Active tab" : "Inactive tab"]
        if isSaved {
            parts.append("saved")
        }
        if hasHighlights {
            parts.append("has highlights")
        }
        if isRead {
            parts.append("read")
        } else if showsProgress {
            let percent = Int((min(max(progress, 0), 1) * 100).rounded())
            parts.append("\(percent)% read")
        }
        return parts.joined(separator: ", ")
    }
}

/// Individual draggable tab item component
private struct DraggableTabItemView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    
    let tab: ArticleTab
    let tabIndex: Int
    let lists: [ReadingList]
    let allLabels: [Label]
    let liquidGlassChrome: Bool
    let isActive: Bool
    let isDragged: Bool
    let dragOffset: CGFloat
    let shiftAmount: CGFloat
    let chromeStyle: TabBarChromeStyle
    let tabWidth: CGFloat
    let interactionProfile: TabInteractionProfile
    let isSaved: Bool
    let hasHighlights: Bool
    let readingProgress: Double
    let showSavedMarker: Bool
    let showHighlightMarker: Bool
    let showReadMarker: Bool
    let showProgressTrack: Bool
    let showActiveDepth: Bool
    let reduceMotion: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onClose: () -> Void
    let onSelect: () -> Void
    let onDragChanged: (CGFloat, CGFloat) -> Void
    let onDragEnded: () -> Void
    
    @State private var isHovered = false
    @State private var showCloseButton = false
    @State private var saveScheduler = DebouncedActionScheduler()
    @GestureState private var isDragActive = false
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    
    /// The most recently used list (for quick save)
    private var recentList: ReadingList? {
        lists.first
    }

    private var matchingSavedArticle: SavedArticle? {
        guard let article = tab.currentArticle else { return nil }
        let targetTitle = ReadStateSync.normalizedTitle(article.title)
        for list in lists {
            if let article = list.articles.first(where: {
                ReadStateSync.normalizedTitle($0.title) == targetTitle
            }) {
                return article
            }
        }
        return nil
    }

    private func requestModelContextSave() {
        saveScheduler.schedule { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    private func flushScheduledModelContextSave() {
        saveScheduler.flush { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }
    
    // MARK: - Drag Animation Settings
    private var liftScale: CGSize {
        isDragged ? CGSize(width: 1.02, height: 1.0) : CGSize(width: 1.0, height: 1.0)
    }
    
    private var liftShadow: CGFloat {
        isDragged ? 8 : 0
    }

    private var showsFavicon: Bool {
        tabWidth >= 98 || isActive
    }

    private var contentSpacing: CGFloat {
        if !showsFavicon && !showCloseButton {
            return 0
        }
        return tabWidth < 95 ? 5 : (chromeStyle.isCompactChrome ? 6 : 8)
    }

    private var horizontalPadding: CGFloat {
        tabWidth < 95 ? 8 : (chromeStyle.isCompactChrome ? 9 : 11)
    }

    private var normalizedProgress: Double {
        min(max(readingProgress, 0), 1)
    }

    private var isReadComplete: Bool {
        normalizedProgress >= 0.995 || tab.currentArticle?.isRead == true
    }

    private var showsSavedMarker: Bool {
        showSavedMarker && isSaved
    }

    private var showsHighlightMarker: Bool {
        showHighlightMarker && hasHighlights
    }

    private var showsReadMarker: Bool {
        showReadMarker && isReadComplete
    }

    private var showsSemanticStatusCluster: Bool {
        !tab.isPlaceholder &&
        chromeStyle.isCompactChrome &&
        tabWidth >= 132 &&
        isActive &&
        (showsSavedMarker || showsHighlightMarker || showsReadMarker)
    }

    private var showsProgressTrack: Bool {
        showProgressTrack &&
        !tab.isPlaceholder &&
        chromeStyle.isCompactChrome &&
        tabWidth >= 132 &&
        isActive &&
        (normalizedProgress > 0.12 || isReadComplete)
    }

    private var tabAccessibilityValue: String {
        TabAccessibilityStatus.value(
            isActive: isActive,
            isSaved: isSaved,
            hasHighlights: hasHighlights,
            isRead: isReadComplete,
            showsProgress: !tab.isPlaceholder && normalizedProgress > 0,
            progress: normalizedProgress
        )
    }

    private var tabHeight: CGFloat {
        switch chromeStyle {
        case .standalone:
            return 34
        case .titlebarAccessory:
            return 30
        case .strip:
            return 28
        }
    }

    private var tabCornerRadius: CGFloat {
        switch chromeStyle {
        case .standalone:
            return 9
        case .titlebarAccessory:
            return 8
        case .strip:
            return 6
        }
    }

    private var closeButtonSize: CGFloat {
        chromeStyle.isCompactChrome ? 18 : 18
    }

    private var closeGlyphSize: CGFloat {
        chromeStyle.isCompactChrome ? 9 : 10
    }

    private var closeButtonBackgroundOpacity: CGFloat {
        guard chromeStyle.isCompactChrome else { return 0 }
        return 0
    }

    private var hasMicroLift: Bool {
        !reduceMotion &&
        showActiveDepth &&
        chromeStyle.isCompactChrome && isActive && !isDragged
    }

    private var restingShadowOpacity: Double {
        hasMicroLift ? TabChromeHierarchy.activeShadowOpacity(darkMode: colorScheme == .dark) : 0
    }

    private var restingShadowRadius: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeShadowRadius() : 0
    }

    private var restingShadowYOffset: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeShadowYOffset() : 0
    }

    private var activeLiftYOffset: CGFloat {
        hasMicroLift ? TabChromeHierarchy.activeLiftYOffset() : 0
    }

    private var activeStrokeWidth: CGFloat {
        chromeStyle.isCompactChrome ? 0.0 : 1.0
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onSelect) {
                HStack(spacing: contentSpacing) {
                    if showsFavicon {
                        faviconView
                    }
                    titleView
                    if showsSemanticStatusCluster {
                        semanticStatusCluster
                    }
                    if showCloseButton {
                        Color.clear
                            .frame(width: closeButtonSize, height: closeButtonSize)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .frame(height: tabHeight)
                .frame(width: tabWidth)
                .background {
                    if usesStripGlassCells && !isDragged {
                        stripGlassCellBackground
                    } else {
                        RoundedRectangle(cornerRadius: tabCornerRadius)
                            .fill(isDragged ? Color(nsColor: .controlBackgroundColor) : backgroundFill)
                    }
                }
                .overlay {
                    if isActive && !isDragged {
                        RoundedRectangle(cornerRadius: tabCornerRadius)
                            .strokeBorder(activeTabStroke, lineWidth: activeStrokeWidth)
                    }
                    if isDragged {
                        RoundedRectangle(cornerRadius: tabCornerRadius)
                            .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
                    }
                }
                .overlay(alignment: .trailing) {
                    if showsStripDivider {
                        Rectangle()
                            .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                            .frame(width: 0.25)
                            .padding(.vertical, 8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsProgressTrack {
                        progressTrackOverlay
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: tabCornerRadius))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(tab.title)
            .accessibilityValue(tabAccessibilityValue)
            .accessibilityHint("Opens this tab")
            .accessibilityAction(named: Text("Close Tab")) {
                onClose()
            }

            closeButtonView
                .padding(.trailing, horizontalPadding)
        }
        // Apply visual effects for drag
        .scaleEffect(liftScale)
        .shadow(
            color: .black.opacity(isDragged ? 0.18 : restingShadowOpacity),
            radius: isDragged ? liftShadow : restingShadowRadius,
            y: isDragged ? 3 : restingShadowYOffset
        )
        .offset(x: isDragged ? dragOffset : shiftAmount, y: activeLiftYOffset)
        .zIndex(isDragged ? 100 : 0)
        .compositingGroup()
        .animation(interactionProfile.neighborShift, value: shiftAmount)
        .animation(interactionProfile.dragLift, value: isDragged)
        // Measure width for drag calculations
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: TabFramePreferenceKey.self,
                        value: [tab.id: geo.frame(in: .named("TabBarSpace"))]
                    )
            }
        )
        .highPriorityGesture(dragGesture)
        .onHover { hovering in
            withAnimation(interactionProfile.hover) {
                isHovered = hovering
            }
            syncCloseButton()
        }
        .onAppear {
            syncCloseButton(animated: false)
        }
        .onDisappear {
            flushScheduledModelContextSave()
        }
        .onChange(of: isActive) { _, _ in
            syncCloseButton()
        }
        .onChange(of: isDragged) { _, _ in
            syncCloseButton()
        }
        .contextMenu {
            contextMenuContent
        }
    }

    private var usesStripGlassCells: Bool {
        chromeStyle.isCompactChrome
    }

    private var showsStripDivider: Bool {
        false
    }

    @ViewBuilder
    private var stripGlassCellBackground: some View {
        let darkMode = colorScheme == .dark
        if liquidGlassChrome {
            let accessoryStyle = chromeStyle == .titlebarAccessory
            let edgeOpacity = darkMode
                ? (isActive ? (accessoryStyle ? 0.072 : 0.086) : (isHovered ? (accessoryStyle ? 0.052 : 0.060) : (accessoryStyle ? 0.036 : 0.042)))
                : (isActive ? (accessoryStyle ? 0.072 : 0.086) : (isHovered ? (accessoryStyle ? 0.054 : 0.064) : (accessoryStyle ? 0.044 : 0.052)))
            let neutralFillOpacity = darkMode
                ? (isActive ? (accessoryStyle ? 0.22 : 0.26) : (isHovered ? (accessoryStyle ? 0.16 : 0.19) : (accessoryStyle ? 0.11 : 0.13)))
                : (isActive ? (accessoryStyle ? 0.50 : 0.56) : (isHovered ? (accessoryStyle ? 0.40 : 0.46) : (accessoryStyle ? 0.31 : 0.36)))
            RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                .fill(AnyShapeStyle(.thinMaterial))
                .overlay {
                    RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(neutralFillOpacity))
                }
                .overlay {
                    if isActive {
                        RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(TabChromeHierarchy.activeGlassTintOpacity(darkMode: darkMode)))
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                        .strokeBorder(Color.primary.opacity(edgeOpacity + (isActive ? 0 : 0.010)), lineWidth: isActive ? 0.46 : 0.44)
                )
        } else {
            let fillOpacity: CGFloat = {
                if darkMode {
                    if isActive { return 0.042 }
                    if isHovered { return 0.012 }
                    return 0.0
                } else {
                    if isActive { return 0.065 }
                    if isHovered { return 0.02 }
                    return 0.0
                }
            }()
            let strokeOpacity: CGFloat = {
                if darkMode {
                    if isActive { return 0.03 }
                    if isHovered { return 0.018 }
                    return 0.012
                } else {
                    if isActive { return 0.075 }
                    if isHovered { return 0.04 }
                    return 0.028
                }
            }()
            RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                .fill((darkMode ? Color.white : Color.black).opacity(fillOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: tabCornerRadius, style: .continuous)
                        .strokeBorder(
                            (darkMode ? Color.white : Color.black).opacity(isActive ? strokeOpacity : strokeOpacity + 0.014),
                            lineWidth: isActive ? 0.50 : 0.46
                        )
                )
        }
    }
    
    private var backgroundFill: Color {
        if isDragged {
            return Color(nsColor: .controlBackgroundColor)
        } else if isActive {
            if chromeStyle == .strip {
                return Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .dark ? 0.62 : 0.78)
            }
            return Color.accentColor.opacity(chromeStyle == .standalone ? 0.10 : 0.14)
        } else if isHovered {
            if chromeStyle == .strip {
                return Color.white.opacity(colorScheme == .dark ? 0.05 : 0.12)
            }
            return Color.primary.opacity(chromeStyle == .standalone ? 0.05 : 0.07)
        }
        return Color.clear
    }

    private var activeTabStroke: AnyShapeStyle {
        if chromeStyle == .strip {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.accentColor.opacity(0.2))
    }
    
    private var dragGesture: some Gesture {
        DragGesture(
            minimumDistance: chromeStyle.isCompactChrome ? 1 : interactionProfile.dragStartDistance,
            coordinateSpace: .named("TabBarSpace")
        )
            .updating($isDragActive) { _, state, _ in
                state = true
            }
            .onChanged { value in
                onDragChanged(value.translation.width, value.location.x)
            }
            .onEnded { _ in
                onDragEnded()
            }
    }
    
    private var faviconView: some View {
        CachedThumbnailImage(url: tab.currentArticle?.thumbnailURL, targetSize: CGSize(width: 16, height: 16)) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            AppLoadingThumbnailPlaceholder(
                width: 16,
                height: 16,
                cornerRadius: 3,
                tone: .neutral,
                symbol: "doc.text.fill"
            )
        } failure: {
            Image(systemName: "doc.text.fill")
                .foregroundStyle(.tertiary)
        }
        .frame(width: chromeStyle == .strip ? 16 : 16, height: chromeStyle == .strip ? 16 : 16)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var semanticStatusCluster: some View {
        HStack(spacing: 3) {
            if showsHighlightMarker {
                Circle()
                    .fill(Color.yellow.opacity(colorScheme == .dark ? 0.78 : 0.70))
                    .frame(width: 4.5, height: 4.5)
            }

            if showsSavedMarker {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.48 : 0.42))
            }

            if showsReadMarker {
                Image(systemName: "checkmark")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.46 : 0.40))
            }
        }
        .padding(.trailing, 1)
        .accessibilityHidden(true)
    }

    private var progressTrackOverlay: some View {
        GeometryReader { proxy in
            let trackWidth = max(10, proxy.size.width - (horizontalPadding * 2))
            let fillWidth = max(1.5, trackWidth * normalizedProgress)
            let darkMode = colorScheme == .dark

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(TabChromeHierarchy.progressTrackOpacity(darkMode: darkMode)))

                Capsule(style: .continuous)
                    .fill(
                        Color.primary
                            .opacity(TabChromeHierarchy.progressFillOpacity(darkMode: darkMode))
                    )
                    .frame(width: fillWidth)
            }
            .frame(width: trackWidth, height: 1.0, alignment: .leading)
            .offset(x: horizontalPadding, y: -2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
    
    private var titleView: some View {
        Text(tab.title)
            .font(
                .system(
                    size: chromeStyle == .strip ? (tabWidth < 95 ? 12 : 12.5) : (tabWidth < 95 ? 12 : 13),
                    weight: chromeStyle == .strip ? (isActive ? .medium : .regular) : (isActive ? .medium : .regular)
                )
            )
            .foregroundStyle(titleForegroundStyle)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleForegroundStyle: AnyShapeStyle {
        if chromeStyle.isCompactChrome {
            let darkMode = colorScheme == .dark
            let titleColor = darkMode ? Color.white : Color.black
            if isActive {
                return AnyShapeStyle(titleColor.opacity(TabChromeHierarchy.titleActiveOpacity(darkMode: darkMode)))
            }
            if isHovered {
                return AnyShapeStyle(titleColor.opacity(TabChromeHierarchy.titleHoverOpacity(darkMode: darkMode)))
            }
            return AnyShapeStyle(titleColor.opacity(TabChromeHierarchy.titleInactiveOpacity(darkMode: darkMode)))
        }
        return AnyShapeStyle(isActive ? Color.primary : Color.secondary)
    }
    
    @ViewBuilder
    private var closeButtonView: some View {
        if showCloseButton {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: closeGlyphSize, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: closeButtonSize, height: closeButtonSize)
                    .background {
                        if chromeStyle == .strip {
                            if closeButtonBackgroundOpacity > 0 {
                                Circle()
                                    .fill(Color.white.opacity(closeButtonBackgroundOpacity))
                            }
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Tab")
            .accessibilityHint("Closes \(tab.title)")
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .scale(scale: chromeStyle == .strip ? 0.92 : 0.86))
            )
        }
    }

    private func syncCloseButton(animated: Bool = true) {
        let shouldShow: Bool
        if chromeStyle.isCompactChrome {
            shouldShow = (isHovered || isActive) && !isDragged
        } else {
            shouldShow = (isHovered || isActive) && !isDragged
        }
        guard shouldShow != showCloseButton else { return }
        if animated {
            let animation = shouldShow ? interactionProfile.closeButtonShow : interactionProfile.closeButtonHide
            withAnimation(animation) {
                showCloseButton = shouldShow
            }
        } else {
            showCloseButton = shouldShow
        }
    }
    
    @ViewBuilder
    private var contextMenuContent: some View {
        // Open actions
        Button {
            duplicateTab()
        } label: {
            SwiftUI.Label("Duplicate Tab", systemImage: "plus.square.on.square")
        }
        .disabled(tab.isPlaceholder)
        
        Divider()
        
        // Quick save to recent list
        if let recent = recentList {
            Button {
                saveToList(recent)
            } label: {
                SwiftUI.Label("Save to \"\(recent.name)\"", systemImage: recent.icon)
            }
        }
        
        // Full list submenu
        if !lists.isEmpty {
            Menu {
                ForEach(lists) { list in
                    Button {
                        saveToList(list)
                    } label: {
                        SwiftUI.Label(list.name, systemImage: list.icon)
                    }
                }
            } label: {
                SwiftUI.Label("Save to List", systemImage: "bookmark")
            }
        }
        
        Divider()

        ArticleQuickActionsMenuContent(title: tab.title)
        
        Divider()
        
        // Label management
        if let savedArticle = matchingSavedArticle {
            if !allLabels.isEmpty {
                Menu {
                    Button {
                        savedArticle.labelId = nil
                        requestModelContextSave()
                    } label: {
                        SwiftUI.Label(
                            "None",
                            systemImage: savedArticle.labelId == nil ? "checkmark.circle" : "circle"
                        )
                    }
                    
                    Divider()
                    
                    ForEach(allLabels) { label in
                        Button {
                            savedArticle.labelId = label.id
                            requestModelContextSave()
                        } label: {
                            SwiftUI.Label {
                                Text(label.name)
                            } icon: {
                                Image(systemName: savedArticle.labelId == label.id ? "checkmark.circle.fill" : "circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(savedArticle.labelId == label.id ? Color.white : label.color.swiftUIColor, label.color.swiftUIColor)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button {
                        onNewLabelWithArticle(savedArticle)
                    } label: {
                        SwiftUI.Label("New Label...", systemImage: "plus")
                    }
                } label: {
                    SwiftUI.Label("Set Label", systemImage: "tag")
                }
                
                Divider()
            }
        }
        
        Divider()
        
        Button {
            closeOtherTabs()
        } label: {
            SwiftUI.Label("Close Other Tabs", systemImage: "xmark.square")
        }
        
        Button("Close Tab", role: .destructive, action: onClose)
    }
    
    private func saveToList(_ list: ReadingList) {
        guard let sourceArticle = tab.currentArticle else { return }
        let normalized = ReadStateSync.normalizedTitle(sourceArticle.title)
        if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalized }) {
            return
        }

        let article = SavedArticle(
            title: sourceArticle.title,
            description: sourceArticle.description,
            extract: sourceArticle.extract,
            thumbnailURL: sourceArticle.thumbnailURL,
            list: list,
            wordCount: sourceArticle.wordCount
        )
        article.isRead = ReadStateSync.resolveReadState(for: sourceArticle, in: modelContext)
        list.articles.append(article)
        list.updatedAt = Date()
        
        modelContext.saveReportingFailure(operation: #function)
        SavedArticleSummaryBackfill.enqueueIfNeeded(article, modelContext: modelContext)
    }
    
    private func duplicateTab() {
        appState.tabSessionStore.duplicateTab(id: tab.id)
    }
    
    private func closeOtherTabs() {
        appState.closeOtherTabs(keeping: tab.id)
    }
    
}

// MARK: - Extensions

private struct TabFramePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct TabContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
