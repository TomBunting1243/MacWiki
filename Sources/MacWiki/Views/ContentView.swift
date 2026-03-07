import SwiftUI
/// Main content view implementing the four-column layout
///
/// Layout:
/// - Column 1: Lists sidebar (reading lists, areas)
/// - Column 2: Directory (list contents or recent articles)
/// - Column 3: Reader (article view with tabs)
/// - Column 4: Inspector (info, notes, graph)
struct ContentView: View {
    private enum LaunchQAHarnessDefaultsKey {
        static let openSidebarSearch = "qa.sidebarSearch.openOnLaunch"
        static let sidebarSearchQuery = "qa.sidebarSearch.queryOnLaunch"
    }

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @State private var selectedList: ReadingList?
    @State private var selectedLabel: Label?
    @State private var selectedTag: Tag?
    @State private var rootSelection: SidebarRootSelection = .recents
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    
    // Label management (Shared)
    @State private var showNewLabelSheet = false
    @State private var editingLabel: Label?
    @State private var articleForNewLabel: SavedArticle?
    
    // Tag management (Shared)
    @State private var showNewTagSheet = false
    @State private var articleForNewTag: Article?
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @AppStorage("listsSidebarWidth") private var listsSidebarWidth: Double = 204
    @AppStorage("inspectorWidth") private var inspectorWidth: Double = 240
    @AppStorage("searchPresentationMode") private var searchPresentationMode: SearchPresentationMode = .overlay
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage("features.wikiHopPostV1Enabled") private var wikiHopPostV1Enabled = false
    @State private var suppressInitialImplicitAnimations = true
    @State private var pendingDetailOnlyEnforcement = false
    @State private var detailOnlyEnforcementRetryCount = 0
    @State private var hasAppliedLaunchQAHarnessOverrides = false
    @State private var renderInspectorColumn = true
    @State private var inspectorColumnExpanded = true

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }

    private enum PanelMotion {
        static let sidebarToggle = ColumnMotion.sidebarVisibility
        static let inspectorToggle = ColumnMotion.inspectorVisibility
        static let inspectorCollapseRemovalDelay: Double = 0.29
        static let detailOnlyEnforcementRetryLimit = 1
        static let searchOverlayToggle = Animation.spring(response: 0.24, dampingFraction: 0.88)
        static let wikiHopSummaryFade = Animation.easeInOut(duration: 0.3)
    }

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    private var resolvedListsSidebarWidth: CGFloat {
        CGFloat(min(max(listsSidebarWidth, 176), 260))
    }

    /// Sidebar toggle collapses all navigation columns in reader mode.
    private var collapsedNavigationVisibility: NavigationSplitViewVisibility {
        .detailOnly
    }

    private var shouldPresentInspectorColumn: Bool {
        !appState.isFocusModeEnabled && appState.inspectorVisible
    }

    private var resolvedInspectorWidth: CGFloat {
        guard shouldPresentInspectorColumn && renderInspectorColumn && inspectorColumnExpanded else { return 0 }
        return CGFloat(min(max(inspectorWidth, 220), 380))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            workspaceSharedBackground
            mainSplitView
            centerToolbarBand
            sidebarTitlebarCap
            sidebarWindowDragOverlay
            inspectorRevealOverlay
            wikiHopOverlay
            searchOverlay
        }
        .toolbar(removing: .title)
        .toolbar(removing: .sidebarToggle)
        .toolbarRole(.editor)
        .toolbar(id: "main-window-toolbar") {
            MainWindowToolbar()
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .animation(reduceMotion ? nil : PanelMotion.searchOverlayToggle, value: appState.showSearch)
        .background {
            WindowTopObscuredHeightReader()
        }
        .contentSheets(
            editingLabel: $editingLabel, 
            showNewLabelSheet: $showNewLabelSheet, 
            articleForNewLabel: $articleForNewLabel,
            showNewTagSheet: $showNewTagSheet,
            articleForNewTag: $articleForNewTag
        )
        .onPreferenceChange(WindowTopObscuredHeightPreferenceKey.self) { newValue in
            let resolved = max(0, newValue)
            if abs(appState.windowTopObscuredHeight - resolved) > 0.5 {
                appState.windowTopObscuredHeight = resolved
            }
        }
        .onAppear {
            applyLaunchQAHarnessOverridesIfNeeded()
            enforceWikiHopAvailabilityIfNeeded()
            syncSidebarVisibilityFromState()
            syncInspectorPresentation(animated: false)
            guard suppressInitialImplicitAnimations else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                suppressInitialImplicitAnimations = false
            }
        }
        .onChange(of: appState.sidebarVisible) { _, _ in
            syncSidebarVisibilityFromState()
        }
        .onChange(of: appState.isFocusModeEnabled) { _, _ in
            syncSidebarVisibilityFromState()
            syncInspectorPresentation()
        }
        .onChange(of: appState.inspectorVisible) { _, _ in
            syncInspectorPresentation()
        }
        .onChange(of: appState.showSearch) { _, isShowingSearch in
            guard isShowingSearch else { return }
            revealSidebarForEmbeddedSearchIfNeeded()
        }
        .onChange(of: searchPresentationMode) { _, _ in
            revealSidebarForEmbeddedSearchIfNeeded()
        }
        .onChange(of: wikiHopPOCEnabled) { _, _ in
            enforceWikiHopAvailabilityIfNeeded()
        }
        .onChange(of: wikiHopPostV1Enabled) { _, _ in
            enforceWikiHopAvailabilityIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewArticleLabel)) { notification in
            guard let article = notification.object as? SavedArticle else { return }
            articleForNewLabel = article
            showNewLabelSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewArticleTag)) { notification in
            guard let article = notification.userInfo?["article"] as? Article else { return }
            articleForNewTag = article
            showNewTagSheet = true
        }
        .onChange(of: columnVisibility) { _, newValue in
            let resolvedSidebarVisible: Bool?
            switch newValue {
            case .all:
                resolvedSidebarVisible = true
            case .doubleColumn, .detailOnly:
                resolvedSidebarVisible = false
            case .automatic:
                resolvedSidebarVisible = nil
            default:
                resolvedSidebarVisible = nil
            }

            if let resolvedSidebarVisible,
               appState.sidebarVisible != resolvedSidebarVisible {
                performAnimation(PanelMotion.sidebarToggle) {
                    appState.sidebarVisible = resolvedSidebarVisible
                }
            }

            enforceDetailOnlyCollapseIfNeeded(for: newValue)
        }
        .onChange(of: appState.isWikiHopNavigationLocked) { _, _ in
            if appState.isWikiHopNavigationLocked {
                // Determine if we need to force close
                if appState.sidebarVisible {
                    performAnimation(PanelMotion.sidebarToggle) {
                        appState.sidebarVisible = false
                    }
                }
            }
        }
        .transaction { transaction in
            if suppressInitialImplicitAnimations {
                transaction.animation = nil
            }
        }
    }

    // MARK: - Layout Components
    
    @ViewBuilder
    private var mainSplitView: some View {
        NavigationSplitView(
            columnVisibility: $columnVisibility
        ) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                preferredWidth: resolvedListsSidebarWidth,
                onEditLabel: { label in editingLabel = label },
                onAddNewLabel: { showNewLabelSheet = true }
            )
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: ListsSidebarWidthPreferenceKey.self, value: geometry.size.width)
                }
            }
        } content: {
            if appState.sidebarVisible {
                DirectoryColumnView(
                    selectedList: $selectedList,
                    rootSelection: $rootSelection,
                    selectedLabel: selectedLabel,
                    selectedTag: selectedTag,
                    onNewLabelWithArticle: { article in
                        articleForNewLabel = article
                        showNewLabelSheet = true
                    },
                    onNewTagWithArticle: { article in
                        articleForNewTag = article
                        showNewTagSheet = true
                    }
                )
            } else {
                // Runtime fallback: some macOS split-view states resolve `.detailOnly`
                // as `.doubleColumn`. Explicitly collapsing the directory column
                // guarantees the toolbar sidebar toggle hides both left columns.
                Color.clear
                    .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 1)
            }
        } detail: {
            mainDetailView
        }
        .onPreferenceChange(ListsSidebarWidthPreferenceKey.self) { newWidth in
            guard appState.sidebarVisible else { return }
            guard newWidth > 1 else { return }
            let clamped = min(max(newWidth, 176), 260)
            if abs(resolvedListsSidebarWidth - clamped) > 0.5 {
                listsSidebarWidth = Double(clamped)
            }
        }
        .background {
            WorkspaceBackdropBackground()
                .ignoresSafeArea()
        }
    }
    
    private var mainDetailView: some View {
        HSplitView {
            ReaderColumnView(
                tabBarLiquidGlass: tabBarLiquidGlass,
                onNewLabelWithArticle: { article in
                    articleForNewLabel = article
                    showNewLabelSheet = true
                }
            )

            if renderInspectorColumn {
                InspectorColumnView(
                    showNewLabelSheet: $showNewLabelSheet,
                    articleForNewLabel: $articleForNewLabel,
                    isExpanded: inspectorColumnExpanded
                )
            }
        }
    }
    
    @ViewBuilder
    private var searchOverlay: some View {
        if appState.showSearch && searchPresentationMode == .overlay {
            GeometryReader { proxy in
                let containerSize = proxy.size
                let clampedWidth = min(QuickSearchView.idealSize.width, containerSize.width * 0.82)
                let clampedHeight = min(QuickSearchView.idealSize.height, containerSize.height * 0.78)
                let modalSize = CGSize(width: clampedWidth, height: clampedHeight)
                let topInset = max(appState.windowTopObscuredHeight + 18, 28)

                ZStack(alignment: .top) {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()
                        .onTapGesture {
                            performAnimation(PanelMotion.searchOverlayToggle) {
                                appState.showSearch = false
                            }
                        }

                    VStack(spacing: 0) {
                        QuickSearchView(modalSize: modalSize)
                            .padding(.top, topInset)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                .transition(AppLoadingMotion.overlayTransition(reduceMotion: reduceMotion, anchor: .top))
            }
        }
    }

    @ViewBuilder
    private var wikiHopOverlay: some View {
        if let session = appState.wikiHopSession {
            if session.status == .active {
                WikiHopOverlay(session: session)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id("wiki-hop-overlay")
            } else if session.status == .completed || session.status == .failed {
                WikiHopSummaryView(session: session)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .opacity.animation(PanelMotion.wikiHopSummaryFade)
                    )
                    .zIndex(100)
            }
        }
    }

    @ViewBuilder
    private var workspaceSharedBackground: some View {
        WorkspaceBackdropBackground()
            .ignoresSafeArea()
    }

    private var chromeRevealTopPadding: CGFloat {
        let topObscuredHeight = max(appState.windowTopObscuredHeight, ColumnChromeMetrics.topBarHeight)
        return max(6, (topObscuredHeight - ChromeIconMetrics.buttonSize) * 0.5)
    }

    @ViewBuilder
    private var centerToolbarBand: some View {
        GeometryReader { proxy in
            let topBandHeight = max(appState.windowTopObscuredHeight, 0)
            let leadingInset = appState.sidebarVisible ? resolvedListsSidebarWidth : 0
            let trailingInset = resolvedInspectorWidth
            let bandWidth = max(0, proxy.size.width - leadingInset - trailingInset)

            if topBandHeight > 0.5 && bandWidth > 0.5 {
                ColumnChromeBackground()
                    .frame(width: bandWidth, height: topBandHeight, alignment: .topLeading)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                            .frame(height: 0.5)
                    }
                    .offset(x: leadingInset)
                    .ignoresSafeArea(.container, edges: .top)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }

    @ViewBuilder
    private var sidebarTitlebarCap: some View {
        if appState.sidebarVisible {
            SidebarPaneBackground()
                .frame(
                    width: resolvedListsSidebarWidth + 1,
                    height: max(appState.windowTopObscuredHeight, 0),
                    alignment: .topLeading
                )
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09))
                        .frame(width: 0.5)
                }
                .ignoresSafeArea(.container, edges: .top)
                .allowsHitTesting(false)
                .zIndex(30)
        }
    }

    private var sidebarDragHeight: CGFloat {
        max(
            appState.windowTopObscuredHeight + ColumnChromeMetrics.topBarHeight + 8,
            ColumnChromeMetrics.titleBarClearance + ColumnChromeMetrics.topBarHeight + 8
        )
    }

    private var sidebarDragWidth: CGFloat {
        let reservedTrailingControls: CGFloat = 52
        return max(96, resolvedListsSidebarWidth - reservedTrailingControls)
    }

    @ViewBuilder
    private var sidebarWindowDragOverlay: some View {
        if appState.sidebarVisible {
            WindowDragHandle(minLength: sidebarDragWidth)
                .frame(width: sidebarDragWidth, height: sidebarDragHeight, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .ignoresSafeArea(.container, edges: .top)
                .zIndex(45)
        }
    }

    @ViewBuilder
    private var inspectorRevealOverlay: some View {
        if !appState.inspectorVisible && appState.isWikiHopNavigationLocked {
            HStack {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                Button {
                    performAnimation(PanelMotion.inspectorToggle) {
                        appState.inspectorVisible = true
                    }
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                        .imageScale(.medium)
                        .foregroundStyle(Color.primary.opacity(0.84))
                        .frame(width: 34, height: ChromeIconMetrics.buttonSize)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    Color(nsColor: .windowBackgroundColor)
                                        .opacity(colorScheme == .dark ? 0.14 : 0.06)
                                }
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.10), lineWidth: 0.7)
                        )
                }
                .buttonStyle(.plain)
                .help("Show Inspector")
                .padding(.trailing, 14)
            }
            .padding(.top, chromeRevealTopPadding)
            .zIndex(50)
        }
    }

    private func syncSidebarVisibilityFromState() {
        let targetVisibility: NavigationSplitViewVisibility = appState.sidebarVisible ? .all : collapsedNavigationVisibility

        if appState.sidebarVisible {
            pendingDetailOnlyEnforcement = false
            detailOnlyEnforcementRetryCount = 0
        } else {
            pendingDetailOnlyEnforcement = true
            detailOnlyEnforcementRetryCount = 0
        }

        guard columnVisibility != targetVisibility else { return }
        performAnimation(PanelMotion.sidebarToggle) {
            columnVisibility = targetVisibility
        }
    }

    private func enforceWikiHopAvailabilityIfNeeded() {
        if !wikiHopPostV1Enabled, wikiHopPOCEnabled {
            appState.setWikiHopExperimentEnabled(false)
        }
        enforceWikiHopRootSelectionIfNeeded()
        if !isWikiHopAvailable {
            appState.dismissWikiHopSession()
        }
    }

    private func enforceWikiHopRootSelectionIfNeeded() {
        guard !isWikiHopAvailable else { return }
        guard rootSelection == .wikiHop else { return }
        rootSelection = .recents
    }

    private func enforceDetailOnlyCollapseIfNeeded(for visibility: NavigationSplitViewVisibility) {
        let targetCollapsedVisibility = collapsedNavigationVisibility

        guard pendingDetailOnlyEnforcement else { return }
        guard !appState.sidebarVisible else {
            pendingDetailOnlyEnforcement = false
            detailOnlyEnforcementRetryCount = 0
            return
        }

        guard visibility != targetCollapsedVisibility else {
            pendingDetailOnlyEnforcement = false
            detailOnlyEnforcementRetryCount = 0
            return
        }

        guard detailOnlyEnforcementRetryCount < PanelMotion.detailOnlyEnforcementRetryLimit else {
            pendingDetailOnlyEnforcement = false
            return
        }

        detailOnlyEnforcementRetryCount += 1

        DispatchQueue.main.async {
            guard pendingDetailOnlyEnforcement else { return }
            guard !appState.sidebarVisible else { return }
            guard columnVisibility != targetCollapsedVisibility else {
                pendingDetailOnlyEnforcement = false
                detailOnlyEnforcementRetryCount = 0
                return
            }

            performAnimation(PanelMotion.sidebarToggle) {
                columnVisibility = targetCollapsedVisibility
            }
        }
    }

    private func revealSidebarForEmbeddedSearchIfNeeded() {
        guard appState.showSearch else { return }
        guard searchPresentationMode == .sidebar else { return }
        guard !appState.isFocusModeEnabled else { return }
        guard !appState.sidebarVisible else { return }
        guard !appState.isWikiHopNavigationLocked else { return }

        performAnimation(PanelMotion.sidebarToggle) {
            appState.sidebarVisible = true
        }
    }

    private func syncInspectorPresentation(animated: Bool = true) {
        let targetVisible = shouldPresentInspectorColumn

        if targetVisible {
            if !renderInspectorColumn {
                renderInspectorColumn = true
                inspectorColumnExpanded = false

                guard animated else {
                    inspectorColumnExpanded = true
                    return
                }

                DispatchQueue.main.async {
                    guard shouldPresentInspectorColumn else { return }
                    performAnimation(PanelMotion.inspectorToggle) {
                        inspectorColumnExpanded = true
                    }
                }
                return
            }

            guard !inspectorColumnExpanded else { return }
            if animated {
                performAnimation(PanelMotion.inspectorToggle) {
                    inspectorColumnExpanded = true
                }
            } else {
                inspectorColumnExpanded = true
            }
            return
        }

        guard renderInspectorColumn else {
            inspectorColumnExpanded = false
            return
        }

        if inspectorColumnExpanded {
            if animated {
                performAnimation(PanelMotion.inspectorToggle) {
                    inspectorColumnExpanded = false
                }
            } else {
                inspectorColumnExpanded = false
            }
        }

        let removalDelay: Double
        if reduceMotion || !animated {
            removalDelay = 0
        } else {
            removalDelay = PanelMotion.inspectorCollapseRemovalDelay
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + removalDelay) {
            guard !shouldPresentInspectorColumn else { return }
            renderInspectorColumn = false
        }
    }

    private func applyLaunchQAHarnessOverridesIfNeeded() {
        guard !hasAppliedLaunchQAHarnessOverrides else { return }
        hasAppliedLaunchQAHarnessOverrides = true

        let defaults = UserDefaults.standard
        let shouldOpenSidebarSearch = defaults.bool(forKey: LaunchQAHarnessDefaultsKey.openSidebarSearch)
        let seededQuery = defaults.string(forKey: LaunchQAHarnessDefaultsKey.sidebarSearchQuery)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Consume keys immediately so harness settings are one-shot and do not leak into normal launches.
        defaults.removeObject(forKey: LaunchQAHarnessDefaultsKey.openSidebarSearch)
        defaults.removeObject(forKey: LaunchQAHarnessDefaultsKey.sidebarSearchQuery)

        guard shouldOpenSidebarSearch || (seededQuery?.isEmpty == false) else { return }

        appState.launchSidebarSearchQuery = seededQuery
        appState.startSearch(context: .navigation)
    }
}
 
extension ContentView {
    // Add logic to enforce sidebar hidden state when locked
    func enforceWikiHopSidebar() {
        if appState.isWikiHopNavigationLocked && appState.sidebarVisible {
            performAnimation(PanelMotion.sidebarToggle) {
                appState.sidebarVisible = false
            }
        }
    }
}

private struct ListsSidebarWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
