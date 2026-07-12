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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedList: ReadingList?
    @State private var selectedLabel: Label?
    @State private var selectedTag: Tag?
    @State private var rootSelection: SidebarRootSelection = .recents
    
    // Label management (Shared)
    @State private var showNewLabelSheet = false
    @State private var editingLabel: Label?
    @State private var articleForNewLabel: SavedArticle?
    
    // Tag management (Shared)
    @State private var showNewTagSheet = false
    @State private var articleForNewTag: Article?
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var wikiHopPostV1Enabled = false
    @State private var suppressInitialImplicitAnimations = true
    @State private var hasAppliedLaunchQAHarnessOverrides = false

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }

    private enum PanelMotion {
        static let sidebarToggle = ColumnMotion.sidebarVisibility
        static let wikiHopSummaryFade = Animation.easeInOut(duration: 0.3)
    }

    private func performAnimation(_ animation: Animation?, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(animation, updates)
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            workspaceSharedBackground
            mainWindowContent
            wikiHopOverlay
        }
        .contentSheets(
            editingLabel: $editingLabel, 
            showNewLabelSheet: $showNewLabelSheet, 
            articleForNewLabel: $articleForNewLabel,
            showNewTagSheet: $showNewTagSheet,
            articleForNewTag: $articleForNewTag
        )
        .onAppear {
            applyLaunchQAHarnessOverridesIfNeeded()
            enforceWikiHopAvailabilityIfNeeded()
            guard suppressInitialImplicitAnimations else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                suppressInitialImplicitAnimations = false
            }
        }
        .onChange(of: appState.showSearch) { _, isShowingSearch in
            guard isShowingSearch else { return }
            revealSidebarForEmbeddedSearchIfNeeded()
        }
        .onChange(of: wikiHopPOCEnabled) { _, _ in
            enforceWikiHopAvailabilityIfNeeded()
        }
        .onChange(of: wikiHopPostV1Enabled) { _, _ in
            enforceWikiHopAvailabilityIfNeeded()
        }
        .onChange(of: appState.newArticleLabelRequest) { _, request in
            guard let request else { return }
            articleForNewLabel = request.article
            showNewLabelSheet = true
        }
        .onChange(of: appState.newArticleTagRequest) { _, request in
            guard let request else { return }
            articleForNewTag = request.article
            showNewTagSheet = true
        }
        .onChange(of: appState.isWikiHopNavigationLocked) { _, _ in
            if appState.isWikiHopNavigationLocked {
                // Determine if we need to force close
                if appState.listsSidebarVisible || appState.directoryColumnVisible {
                    performAnimation(PanelMotion.sidebarToggle) {
                        appState.setNavigationColumnsVisible(false)
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

    private var mainWindowContent: some View {
        mainSplitView
    }

    // MARK: - Layout Components
    
    @ViewBuilder
    private var mainSplitView: some View {
        MainWindowShell(
            selectedList: $selectedList,
            selectedLabel: $selectedLabel,
            selectedTag: $selectedTag,
            rootSelection: $rootSelection,
            showNewLabelSheet: $showNewLabelSheet,
            articleForNewLabel: $articleForNewLabel,
            onEditLabel: { label in editingLabel = label },
            onAddNewLabel: { showNewLabelSheet = true },
            onNewLabelWithArticle: { article in
                articleForNewLabel = article
                showNewLabelSheet = true
            },
            onNewTagWithArticle: { article in
                articleForNewTag = article
                showNewTagSheet = true
            }
        )
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
            .ignoresSafeArea(.container, edges: [.leading, .trailing, .bottom])
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

    private func revealSidebarForEmbeddedSearchIfNeeded() {
        guard appState.showSearch else { return }
        guard !appState.listsSidebarVisible || !appState.directoryColumnVisible else { return }
        guard !appState.isWikiHopNavigationLocked else { return }

        performAnimation(PanelMotion.sidebarToggle) {
            appState.setNavigationColumnsVisible(true)
        }
    }

    private func applyLaunchQAHarnessOverridesIfNeeded() {
        guard !hasAppliedLaunchQAHarnessOverrides else { return }
        hasAppliedLaunchQAHarnessOverrides = true

        let defaults = MacWikiDefaults.current
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
        if appState.isWikiHopNavigationLocked && (appState.listsSidebarVisible || appState.directoryColumnVisible) {
            performAnimation(PanelMotion.sidebarToggle) {
                appState.setNavigationColumnsVisible(false)
            }
        }
    }
}
