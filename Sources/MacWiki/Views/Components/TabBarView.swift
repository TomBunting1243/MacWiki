import SwiftUI
import SwiftData

/// Horizontal scrollable tab bar for managing open articles
struct TabBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(TabAccompanimentStorageKey.showSavedMarker) private var showSavedTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showHighlightMarker) private var showHighlightTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showReadMarker) private var showReadTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showProgressTrack) private var showTabProgressTrack = true
    @AppStorage(TabAccompanimentStorageKey.showActiveDepth) private var showTabActiveDepth = true
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var lists: [ReadingList]
    @Query(sort: \Label.sortOrder) private var allLabels: [Label]
    @Query(sort: \Highlight.updatedAt, order: .reverse) private var highlights: [Highlight]
    let showsTopDivider: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void
    
    // MARK: - Drag State
    @State private var draggedTabId: UUID?
    @State private var draggedSourceIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    // MARK: - Performance: Memoized target position
    /// Only changes when drag crosses a tab boundary, not every pixel
    @State private var currentTargetIndex: Int = 0

    // MARK: - Overflow + Scroll
    @State private var tabsViewportWidth: CGFloat = 0
    @State private var tabsViewportFrame: CGRect = .zero
    @State private var pendingScrollTabId: UUID?
    @State private var lastDragAutoScrollTimestamp: TimeInterval = 0
    @State private var libraryIndex = TabBarLibraryIndex()

    private var minimumTabsContentWidth: CGFloat {
        let tabCount = appState.openTabs.count
        guard tabCount > 0 else { return 0 }
        return (CGFloat(tabCount) * ReaderTabLaneMetrics.tabMinWidth)
            + (CGFloat(max(0, tabCount - 1)) * tabSpacing)
    }

    private var tabsContentWidth: CGFloat {
        let tabCount = appState.openTabs.count
        guard tabCount > 0 else { return 0 }
        return (CGFloat(tabCount) * resolvedTabWidth)
            + (CGFloat(max(0, tabCount - 1)) * tabSpacing)
    }

    private var tabFrames: [UUID: CGRect] {
        TabBarDragPlanner.frames(
            for: appState.openTabs.map(\.id),
            tabWidth: resolvedTabWidth,
            tabSpacing: tabSpacing,
            tabHeight: ReaderTabLaneMetrics.height
        )
    }

    private var showsOverflowMenu: Bool {
        tabsViewportWidth > 0 && minimumTabsContentWidth > (tabsViewportWidth + 1)
    }

    private var interactionProfile: TabInteractionProfile {
        TabInteractionProfile.resolve(
            for: tabsViewportWidth,
            reduceMotion: accessibilityPersonalization.reduceMotion
        )
    }

    private var reduceMotion: Bool {
        accessibilityPersonalization.reduceMotion
    }

    private var tabSpacing: CGFloat {
        ReaderTabLaneMetrics.tabSpacing
    }

    private var resolvedTabWidth: CGFloat {
        let viewport = tabsViewportWidth > 0 ? tabsViewportWidth : 900
        // The ScrollView has already received the width left after the native
        // New Tab/overflow ControlGroup. Reserving those controls again creates
        // dead space and forces tabs to compress prematurely.
        let available = max(200, viewport)
        let tabCount = max(1, appState.openTabs.count)
        let totalSpacing = tabSpacing * CGFloat(max(0, tabCount - 1))
        let proportional = (available - totalSpacing) / CGFloat(tabCount)
        return min(
            max(proportional, ReaderTabLaneMetrics.tabMinWidth),
            ReaderTabLaneMetrics.tabMaxWidth
        )
    }

    init(
        showsTopDivider: Bool = true,
        onNewLabelWithArticle: @escaping (SavedArticle) -> Void
    ) {
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
        let librarySnapshot = libraryIndex.snapshot(
            lists: lists,
            highlights: highlights
        )

        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    tabItemsStack(
                        librarySnapshot: librarySnapshot
                    )
                    .coordinateSpace(name: "TabBarSpace")
                }
                .scrollIndicators(.hidden)
                // The tab's high-priority gesture owns an active drag. Changing
                // the parent scroll recognizer from that child-owned state
                // creates an AttributeGraph cycle in optimized macOS 27 builds.
                .scrollClipDisabled()
                .onScrollGeometryChange(for: CGRect.self) { geometry in
                    geometry.visibleRect
                } action: { _, visibleRect in
                    updateTabsViewportWidth(visibleRect.width)
                    updateTabsViewportFrame(visibleRect)
                }
                .onAppear {
                    scrollToActiveTab(with: proxy, animated: false)
                }
                .onChange(of: appState.activeTabId) { _, _ in
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

            ReaderTabAccessoryCluster(
                showsOverflowMenu: showsOverflowMenu,
                interactionProfile: interactionProfile
            )
        }
        .padding(.horizontal, ReaderTabLaneMetrics.horizontalPadding)
        .padding(.vertical, ReaderTabLaneMetrics.verticalPadding)
        .frame(height: ReaderTabLaneMetrics.height)
        .background(tabBarBackground)
        .animation(interactionProfile.overflowAffordance, value: showsOverflowMenu)
    }

    @ViewBuilder
    private func tabItemsStack(
        librarySnapshot: TabBarLibraryIndex.Snapshot
    ) -> some View {
        let indexByID = tabIndexByID

        // SDK 27's native reorder container fatals on the current macOS 27
        // seed with "Unexpected identifier type" even when the ForEach and
        // itemID key path use the same UUID or String type. Keep this bounded
        // SwiftUI gesture path on both supported OS versions until a later seed
        // passes the packaged drag, overflow, persistence, and relaunch gate.
        HStack(spacing: tabSpacing) {
            ForEach(appState.openTabs) { tab in
                tabItem(
                    tab,
                    at: indexByID[tab.id] ?? 0,
                    librarySnapshot: librarySnapshot
                )
            }
        }
    }

    private func tabItem(
        _ tab: ArticleTab,
        at index: Int,
        librarySnapshot: TabBarLibraryIndex.Snapshot
    ) -> some View {
        ReaderTabItemView(
            tab: tab,
            lists: lists,
            allLabels: allLabels,
            isActive: appState.activeTabId == tab.id,
            isDragged: draggedTabId == tab.id,
            dragOffset: draggedTabId == tab.id ? dragOffset : 0,
            shiftAmount: shiftAmount(for: index),
            tabWidth: resolvedTabWidth,
            interactionProfile: interactionProfile,
            matchingSavedArticle: savedArticle(
                for: tab,
                in: librarySnapshot.savedArticleByTitle
            ),
            hasHighlights: hasHighlights(
                tab,
                highlightedTitles: librarySnapshot.highlightedTitles
            ),
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
                    appState.selectTab(tab.id)
                }
            },
            onDragChanged: { translation, locationX in
                handleDragChanged(
                    tab: tab,
                    at: index,
                    translation: translation,
                    dragLocationX: locationX
                )
            },
            onDragEnded: {
                finalizeDrag()
            }
        )
    }

    private var tabIndexByID: [UUID: Int] {
        Dictionary(
            uniqueKeysWithValues: appState.openTabs.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    @ViewBuilder
    private var tabBarBackground: some View {
        Color.clear
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
            performAnimation(interactionProfile.dragLift) {
                draggedTabId = tab.id
                draggedSourceIndex = index
                currentTargetIndex = index
            }
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
    private func finalizeDrag() {
        let sourceIndex = draggedSourceIndex
        let targetIndex = currentTargetIndex

        guard targetIndex != sourceIndex else {
            performAnimation(interactionProfile.snapBack) {
                resetDragState()
            }
            return
        }

        // End the gesture event before changing the ForEach collection order.
        // Clear the transient drag graph first, then publish the model reorder
        // in the same animation-disabled transaction so rows never recompute
        // against a new index while still carrying old drag offsets.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1))
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                resetDragState()
                appState.moveTab(from: sourceIndex, to: targetIndex)
            }
        }
    }

    private func resetDragState() {
        dragOffset = 0
        draggedTabId = nil
        currentTargetIndex = 0
        pendingScrollTabId = nil
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

    private func savedArticle(
        for tab: ArticleTab,
        in savedArticleByTitle: [String: SavedArticle]
    ) -> SavedArticle? {
        guard !tab.isPlaceholder else { return nil }
        return savedArticleByTitle[normalizedTitle(for: tab)]
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
