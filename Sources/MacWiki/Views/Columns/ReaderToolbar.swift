import SwiftUI
import SwiftData
import AppKit

private enum ToolbarHierarchy {
    static func iconPrimaryOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.68 : 0.62
    }

    static func iconSelectedOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.84 : 0.78
    }

    static func iconHoverOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.78 : 0.72
    }

    static func iconDisabledOpacity() -> Double {
        0.30
    }

    static func normalizedSymbolWeight(isFilled: Bool) -> Font.Weight {
        return isFilled ? .regular : .medium
    }

    static func normalizedSymbolSize(base: CGFloat, isFilled: Bool) -> CGFloat {
        return isFilled ? (base - 0.35) : base
    }

    static func groupSelectedFillOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.055 : 0.035
    }

    static func groupSelectedStrokeOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.10 : 0.075
    }

    static func groupSelectedGlassSheenOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.06 : 0.10
    }

    static func groupHoverFillOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.05 : 0.035
    }

    static func groupHoverStrokeOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.10 : 0.075
    }
}

/// Fixed toolbar rendered as a SwiftUI HStack inside the reader column's
/// top chrome lane.  Replaces the former native NSToolbar items.
struct ReaderToolbar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @State private var showSavePopover = false
    @State private var showReaderStylePopover = false
    @State private var showStatsPopover = false
    @State private var hoveredPillID: String?

    // MARK: - Derived state

    private var currentTab: ArticleTab? {
        guard let activeId = appState.activeTabId else { return nil }
        return appState.openTabs.first(where: { $0.id == activeId })
    }

    private var currentArticle: Article? {
        appState.currentArticle
    }

    private var hasArticle: Bool {
        currentArticle != nil
    }

    private var isRead: Bool {
        currentArticle?.isRead ?? false
    }

    private var isSavedInAnyList: Bool {
        guard let article = currentArticle else { return false }
        let normalized = ReadStateSync.normalizedTitle(article.title)
        return allLists.contains { list in
            list.articles.contains { ReadStateSync.normalizedTitle($0.title) == normalized }
        }
    }

    private var navigationLocked: Bool {
        appState.isWikiHopNavigationLocked
    }

    private enum ToolbarOverflowAction: String, Hashable {
        case pageViews
        case openInBrowser
        case inspector
    }

    private enum ToolbarPriorityTier {
        case spacious
        case regular
        case compact
        case ultraCompact

        static func resolve(for width: CGFloat) -> ToolbarPriorityTier {
            if width < 760 { return .ultraCompact }
            if width < 900 { return .compact }
            if width < 1060 { return .regular }
            return .spacious
        }

        var showsFindInline: Bool {
            true
        }

        var showsReadInline: Bool {
            true
        }

        var showsShareInline: Bool {
            true
        }

        var showsStatsInline: Bool {
            switch self {
            case .spacious:
                return true
            case .regular, .compact, .ultraCompact:
                return false
            }
        }

        var showsOpenInBrowserInline: Bool {
            switch self {
            case .spacious:
                return true
            case .regular, .compact, .ultraCompact:
                return false
            }
        }

        var showsReaderStyleInline: Bool {
            true
        }

        var showsFocusModeInline: Bool {
            true
        }

        var showsInspectorInline: Bool {
            switch self {
            case .spacious, .regular:
                return true
            case .compact, .ultraCompact:
                return false
            }
        }
    }

    private let groupedControlHeight: CGFloat = TopChromeControlMetrics.groupHeight
    private let groupedControlButtonSize: CGFloat = TopChromeControlMetrics.groupButtonSize
    private let groupedControlSymbolSize: CGFloat = ChromeIconMetrics.symbolPointSize

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { proxy in
            toolbarContent(for: ToolbarPriorityTier.resolve(for: proxy.size.width))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
        }
    }

    @ViewBuilder
    private func toolbarContent(for tier: ToolbarPriorityTier) -> some View {
        let overflowActions = overflowActions(for: tier)

        HStack(spacing: 8) {
            HStack(spacing: 4) {
                toolbarMicroPill(
                    id: "left-sidebar",
                    isEnabled: !navigationLocked,
                    isActive: appState.sidebarVisible && !navigationLocked
                ) {
                    toolbarButton(
                        symbol: "sidebar.leading",
                        label: appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns",
                        enabled: !navigationLocked,
                        isActive: appState.sidebarVisible && !navigationLocked,
                        isHovered: hoveredPillID == "left-sidebar"
                    ) {
                        performAnimation(ColumnMotion.sidebarVisibility) {
                            appState.sidebarVisible.toggle()
                        }
                    }
                }

                toolbarMicroPill(id: "left-back", isEnabled: currentTab?.canGoBack ?? false) {
                    toolbarButton(
                        symbol: "chevron.left",
                        label: "Back",
                        enabled: currentTab?.canGoBack ?? false,
                        isHovered: hoveredPillID == "left-back"
                    ) {
                        appState.goBack()
                    }
                }

                toolbarMicroPill(id: "left-forward", isEnabled: currentTab?.canGoForward ?? false) {
                    toolbarButton(
                        symbol: "chevron.right",
                        label: "Forward",
                        enabled: currentTab?.canGoForward ?? false,
                        isHovered: hoveredPillID == "left-forward"
                    ) {
                        appState.goForward()
                    }
                }

                toolbarMicroPill(
                    id: "left-find",
                    isEnabled: hasArticle,
                    isActive: hasArticle && appState.showFindOnPage
                ) {
                    toolbarButton(
                        symbol: "magnifyingglass",
                        label: "Find in Page",
                        enabled: hasArticle,
                        isActive: hasArticle && appState.showFindOnPage,
                        isHovered: hoveredPillID == "left-find"
                    ) {
                        toggleFindOnPage()
                    }
                }

                toolbarMicroPill(
                    id: "left-save",
                    isEnabled: hasArticle,
                    isActive: hasArticle && isSavedInAnyList
                ) {
                    toolbarButton(
                        symbol: isSavedInAnyList ? "bookmark.fill" : "bookmark",
                        label: "Save",
                        enabled: hasArticle,
                        isActive: hasArticle && isSavedInAnyList,
                        isHovered: hoveredPillID == "left-save"
                    ) {
                        showSavePopover = true
                    }
                }
                .popover(isPresented: $showSavePopover, arrowEdge: .bottom) {
                    if let article = currentArticle {
                        SaveToListPopover(
                            articleTitle: article.title,
                            articleDescription: article.description,
                            articleExtract: article.extract,
                            thumbnailURL: article.thumbnailURL,
                            articleWordCount: article.wordCount
                        )
                    }
                }

                toolbarMicroPill(
                    id: "left-read",
                    isEnabled: hasArticle,
                    isActive: hasArticle && isRead
                ) {
                    toolbarButton(
                        symbol: isRead ? "checkmark.circle.fill" : "circle",
                        label: isRead ? "Mark as Unread" : "Mark as Read",
                        enabled: hasArticle,
                        isActive: hasArticle && isRead,
                        isHovered: hoveredPillID == "left-read"
                    ) {
                        toggleRead()
                    }
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if tier.showsFocusModeInline {
                    toolbarMicroPill(
                        id: "right-focus",
                        isEnabled: hasArticle && !navigationLocked,
                        isActive: appState.isFocusModeEnabled
                    ) {
                        toolbarButton(
                            symbol: "viewfinder",
                            label: appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
                            enabled: hasArticle && !navigationLocked,
                            isActive: appState.isFocusModeEnabled,
                            isHovered: hoveredPillID == "right-focus"
                        ) {
                            appState.toggleFocusMode()
                        }
                    }
                }

                if tier.showsStatsInline {
                    toolbarMicroPill(
                        id: "right-stats",
                        isEnabled: hasArticle,
                        isActive: hasArticle && showStatsPopover
                    ) {
                        toolbarButton(
                            symbol: "chart.xyaxis.line",
                            label: "Show Page Views",
                            enabled: hasArticle,
                            isActive: hasArticle && showStatsPopover,
                            isHovered: hoveredPillID == "right-stats"
                        ) {
                            guard hasArticle else { return }
                            showStatsPopover.toggle()
                        }
                    }
                    .popover(isPresented: $showStatsPopover, arrowEdge: .bottom) {
                        if let article = currentArticle {
                            SidebarPageViewsPopoverContent(
                                title: article.title,
                                referenceDate: Date()
                            )
                        }
                    }
                }

                if tier.showsReaderStyleInline {
                    toolbarMicroPill(id: "right-style") {
                        toolbarButton(
                            symbol: "textformat.size",
                            label: "Reader Style",
                            enabled: true,
                            isHovered: hoveredPillID == "right-style"
                        ) {
                            showReaderStylePopover = true
                        }
                    }
                    .popover(isPresented: $showReaderStylePopover, arrowEdge: .bottom) {
                        ReaderStylePopover()
                    }
                }

                if tier.showsOpenInBrowserInline {
                    toolbarMicroPill(id: "right-browser", isEnabled: hasArticle) {
                        toolbarButton(
                            symbol: "safari",
                            label: "Open in Browser",
                            enabled: hasArticle,
                            isHovered: hoveredPillID == "right-browser"
                        ) {
                            openCurrentArticleInBrowser()
                        }
                    }
                }

                if tier.showsShareInline {
                    toolbarMicroPill(id: "right-share", isEnabled: hasArticle) {
                        ShareToolbarButton(
                            articleURL: currentArticle?.url,
                            symbolSize: groupedControlSymbolSize,
                            buttonSize: groupedControlButtonSize,
                            isHovered: hoveredPillID == "right-share"
                        )
                        .disabled(!hasArticle)
                    }
                }

                if tier.showsInspectorInline {
                    toolbarMicroPill(id: "right-inspector", isActive: appState.inspectorVisible) {
                        toolbarButton(
                            symbol: "sidebar.trailing",
                            label: appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                            enabled: true,
                            isActive: appState.inspectorVisible,
                            isHovered: hoveredPillID == "right-inspector"
                        ) {
                            toggleInspector()
                        }
                    }
                }

                if !overflowActions.isEmpty {
                    toolbarMicroPill(id: "right-overflow") {
                        overflowMenuButton(
                            actions: overflowActions,
                            isHovered: hoveredPillID == "right-overflow"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func toggleRead() {
        guard let article = currentArticle else { return }
        let nextState = !isRead
        _ = ReadStateSync.applyReadState(nextState, for: article, in: modelContext, appState: appState)
    }

    private func openCurrentArticleInBrowser() {
        guard let article = currentArticle else { return }
        openURL(article.url)
    }

    private func toggleInspector() {
        performAnimation(ColumnMotion.inspectorVisibility) {
            appState.toggleInspectorVisibility()
        }
    }

    private func toggleFindOnPage() {
        guard hasArticle, let tabID = appState.activeTabId else { return }

        performAnimation(TopChromeMotion.tabSelect(density: .regular, strip: true)) {
            if appState.showFindOnPage {
                appState.showFindOnPage = false
                appState.findOnPageQuery = ""
                appState.findOnPageMatchFound = nil
                appState.pendingFindOnPageRequest = AppState.FindOnPageRequest(
                    requestID: UUID(),
                    tabID: tabID,
                    query: "",
                    backwards: false
                )
            } else {
                appState.showFindOnPage = true
                appState.findOnPageMatchFound = nil
            }
        }
    }

    // MARK: - Button builder

    private func iconColor(enabled: Bool, isActive: Bool, isHovered: Bool = false) -> Color {
        let darkMode = colorScheme == .dark
        guard enabled else {
            return Color.primary.opacity(ToolbarHierarchy.iconDisabledOpacity())
        }
        if isActive {
            return Color.primary.opacity(ToolbarHierarchy.iconSelectedOpacity(darkMode: darkMode))
        }
        if isHovered {
            return Color.primary.opacity(ToolbarHierarchy.iconHoverOpacity(darkMode: darkMode))
        }
        return Color.primary.opacity(ToolbarHierarchy.iconPrimaryOpacity(darkMode: darkMode))
    }

    @ViewBuilder
    private func toolbarButton(
        symbol: String,
        label: String,
        enabled: Bool,
        isActive: Bool = false,
        isHovered: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let filledSymbol = symbol.contains(".fill")
        let symbolWeight = ToolbarHierarchy.normalizedSymbolWeight(isFilled: filledSymbol)
        let symbolSize = ToolbarHierarchy.normalizedSymbolSize(
            base: groupedControlSymbolSize,
            isFilled: filledSymbol
        )

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: symbolWeight))
                .imageScale(.medium)
                .foregroundStyle(
                    iconColor(
                        enabled: enabled,
                        isActive: isActive && enabled,
                        isHovered: isHovered && !isActive && enabled
                    )
                )
                .frame(width: groupedControlButtonSize, height: groupedControlButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(label)
    }

    private func toolbarPill<Content: View>(
        id: String,
        horizontalPadding: CGFloat = TopChromeControlMetrics.groupHorizontalPadding,
        isEnabled: Bool = true,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let darkMode = colorScheme == .dark
        let isHovered = isEnabled && hoveredPillID == id

        return HStack(spacing: TopChromeControlMetrics.groupInnerSpacing) {
            content()
        }
        .padding(.horizontal, horizontalPadding)
        .frame(height: groupedControlHeight)
        .background {
            ZStack {
                if tabBarLiquidGlass {
                    RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay {
                            RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                .fill(
                                    Color(nsColor: .windowBackgroundColor)
                                        .opacity(darkMode ? 0.16 : 0.09)
                                )
                                .allowsHitTesting(false)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(darkMode ? 0.05 : 0.08),
                                            Color.clear
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .blendMode(.screen)
                                .allowsHitTesting(false)
                        }
                } else {
                    RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.70 : 0.84))
                        .overlay {
                            RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: darkMode
                                            ? [
                                                Color.white.opacity(0.05),
                                                Color.clear
                                            ]
                                            : [
                                                Color.white.opacity(0.26),
                                                Color.white.opacity(0.10)
                                            ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .allowsHitTesting(false)
                        }
                }

                if isActive {
                    if tabBarLiquidGlass {
                        RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                    .fill(
                                        Color.accentColor.opacity(
                                            ToolbarHierarchy.groupSelectedFillOpacity(darkMode: darkMode)
                                        )
                                    )
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(
                                                    ToolbarHierarchy.groupSelectedGlassSheenOpacity(darkMode: darkMode)
                                                ),
                                                Color.clear
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .blendMode(.screen)
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                    .strokeBorder(
                                        Color.accentColor.opacity(
                                            ToolbarHierarchy.groupSelectedStrokeOpacity(darkMode: darkMode)
                                        ),
                                        lineWidth: 0.58
                                    )
                            )
                            .allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                            .fill(Color.accentColor.opacity(ToolbarHierarchy.groupSelectedFillOpacity(darkMode: darkMode)))
                            .overlay(
                                RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                                    .strokeBorder(
                                        Color.accentColor.opacity(
                                            ToolbarHierarchy.groupSelectedStrokeOpacity(darkMode: darkMode)
                                        ),
                                        lineWidth: 0.56
                                    )
                            )
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.primary.opacity(
                        TopChromeControlSurface.borderOpacity(
                            darkMode: darkMode,
                            liquid: tabBarLiquidGlass
                        )
                    ),
                    lineWidth: tabBarLiquidGlass ? 0.48 : 0.54
                )
                .allowsHitTesting(false)
        )
        .overlay {
            if isHovered {
                RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(ToolbarHierarchy.groupHoverFillOpacity(darkMode: darkMode)))
                    .overlay(
                        RoundedRectangle(cornerRadius: TopChromeControlMetrics.groupCornerRadius, style: .continuous)
                            .strokeBorder(
                                Color.primary.opacity(
                                    ToolbarHierarchy.groupHoverStrokeOpacity(darkMode: darkMode)
                                ),
                                lineWidth: 0.56
                            )
                    )
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering in
            guard isEnabled else {
                if hoveredPillID == id {
                    hoveredPillID = nil
                }
                return
            }
            if hovering {
                hoveredPillID = id
            } else if hoveredPillID == id {
                hoveredPillID = nil
            }
        }
        .modifier(PointingHandCursorModifier(isEnabled: isEnabled))
    }

    private func toolbarMicroPill<Content: View>(
        id: String,
        isEnabled: Bool = true,
        isActive: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        toolbarPill(
            id: id,
            horizontalPadding: max(3, TopChromeControlMetrics.groupHorizontalPadding - 5),
            isEnabled: isEnabled,
            isActive: isActive,
            content: content
        )
    }

    private func overflowActions(for tier: ToolbarPriorityTier) -> [ToolbarOverflowAction] {
        var actions: [ToolbarOverflowAction] = []

        if !tier.showsStatsInline {
            actions.append(.pageViews)
        }

        if !tier.showsOpenInBrowserInline {
            actions.append(.openInBrowser)
        }

        if !tier.showsInspectorInline {
            actions.append(.inspector)
        }

        return actions
    }

    @ViewBuilder
    private func overflowMenuButton(
        actions: [ToolbarOverflowAction],
        isHovered: Bool
    ) -> some View {
        Menu {
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                switch action {
                case .pageViews:
                    Button {
                        guard hasArticle else { return }
                        showStatsPopover = true
                    } label: {
                        SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                    }
                    .disabled(!hasArticle)
                case .openInBrowser:
                    Button {
                        openCurrentArticleInBrowser()
                    } label: {
                        SwiftUI.Label("Open in Browser", systemImage: "safari")
                    }
                    .disabled(!hasArticle)
                case .inspector:
                    Button {
                        toggleInspector()
                    } label: {
                        SwiftUI.Label(
                            appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                            systemImage: "sidebar.trailing"
                        )
                    }
                }
            }
        } label: {
            SwiftUI.Label("More Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.system(size: groupedControlSymbolSize, weight: .medium))
                .imageScale(.medium)
                .foregroundStyle(iconColor(enabled: true, isActive: false, isHovered: isHovered))
                .frame(width: groupedControlButtonSize, height: groupedControlButtonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("More Actions")
    }
}

private struct PointingHandCursorModifier: ViewModifier {
    let isEnabled: Bool
    @State private var didPushCursor = false

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                guard isEnabled else {
                    if didPushCursor {
                        NSCursor.pop()
                        didPushCursor = false
                    }
                    return
                }

                if hovering && !didPushCursor {
                    NSCursor.pointingHand.push()
                    didPushCursor = true
                } else if !hovering && didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
            .onDisappear {
                if didPushCursor {
                    NSCursor.pop()
                    didPushCursor = false
                }
            }
    }
}

// MARK: - Share button

private struct ShareToolbarButton: View {
    let articleURL: URL?
    let symbolSize: CGFloat
    let buttonSize: CGFloat
    let isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let articleURL {
            ShareLink(item: articleURL) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: symbolSize, weight: .medium))
                    .imageScale(.medium)
                    .foregroundStyle(
                        Color.primary.opacity(
                            isHovered
                                ? ToolbarHierarchy.iconHoverOpacity(darkMode: colorScheme == .dark)
                                : ToolbarHierarchy.iconPrimaryOpacity(darkMode: colorScheme == .dark)
                        )
                    )
                    .frame(width: buttonSize, height: buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Share")
        } else {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: symbolSize, weight: .medium))
                .imageScale(.medium)
                .foregroundStyle(Color.primary.opacity(ToolbarHierarchy.iconDisabledOpacity()))
                .frame(width: buttonSize, height: buttonSize)
        }
    }
}
