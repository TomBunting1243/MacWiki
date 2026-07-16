import SwiftData
import SwiftUI

struct MainWindowShell: View {
    @Environment(AppState.self) private var appState
    @State private var sidebarSearchModel = SidebarSearchSurfaceModel()

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        MainWorkspaceShell(
            selectedList: $selectedList,
            selectedLabel: $selectedLabel,
            selectedTag: $selectedTag,
            rootSelection: $rootSelection,
            sidebarSearchModel: sidebarSearchModel,
            onEditLabel: onEditLabel,
            onAddNewLabel: onAddNewLabel,
            onNewLabelWithArticle: onNewLabelWithArticle,
            onNewTagWithArticle: onNewTagWithArticle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The main window uses one platform-owned AppKit split for Lists, List
/// Contents, Reader, and a full-height Inspector. Every auxiliary pane remains
/// independently collapsible while the Reader and its WebView stay mounted.
private struct MainWorkspaceShell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.MainWindow.sidebarWidth) private var sidebarWidth = AppStorageKey.MainWindow.sidebarWidthDefault
    @AppStorage(AppStorageKey.MainWindow.directoryWidth) private var directoryWidth = AppStorageKey.MainWindow.directoryWidthDefault
    @AppStorage(AppStorageKey.MainWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.MainWindow.inspectorWidthDefault
    @State private var openWindowHandler = WorkspaceOpenWindowHandler()
    @State private var showsSavePopover = false
    @State private var showsReaderStylePopover = false
    @State private var showsPageViewsPopover = false

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    let sidebarSearchModel: SidebarSearchSurfaceModel
    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        @Bindable var appState = appState

        AppKitWorkspaceNavigationSplitView(
            listsVisible: $appState.listsSidebarVisible,
            directoryVisible: $appState.directoryColumnVisible,
            inspectorVisible: $appState.inspectorVisible,
            reduceMotion: accessibilityPersonalization.reduceMotion,
            initialListsWidth: CGFloat(sidebarWidth),
            initialDirectoryWidth: CGFloat(directoryWidth),
            initialInspectorWidth: CGFloat(inspectorWidth),
            listsRevision: workspaceAppearanceRevision,
            directoryRevision: directoryContentRevision,
            readerRevision: workspaceAppearanceRevision,
            inspectorRevision: workspaceAppearanceRevision,
            readerAccessoryRevision: workspaceAppearanceRevision,
            lists: workspaceEnvironment(
                ListsColumnView(
                    selectedList: $selectedList,
                    selectedLabel: $selectedLabel,
                    selectedTag: $selectedTag,
                    rootSelection: $rootSelection,
                    sidebarSearchModel: sidebarSearchModel,
                    onEditLabel: onEditLabel,
                    onAddNewLabel: onAddNewLabel
                )
            ),
            directory: workspaceEnvironment(
                DirectoryColumnView(
                    selectedList: $selectedList,
                    rootSelection: $rootSelection,
                    selectedLabel: selectedLabel,
                    selectedTag: selectedTag,
                    sidebarSearchModel: sidebarSearchModel,
                    onNewLabelWithArticle: onNewLabelWithArticle,
                    onNewTagWithArticle: onNewTagWithArticle
                )
            ),
            reader: workspaceEnvironment(
                ReaderColumnView()
                    .id("main-reader-column")
            ),
            inspector: workspaceEnvironment(
                InspectorColumnView()
            ),
            readerAccessory: workspaceEnvironment(
                TabBarView(
                    showsTopDivider: false,
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
            )
        )
        // The semantic AppKit Sidebar and Inspector own full-height titlebar
        // integration. Give the split the whole window surface; AppKit applies
        // native safe-area insets to pane content and accessory controls.
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            MainWindowReaderToolbar(
                appState: appState,
                modelContext: modelContext,
                showsSavePopover: $showsSavePopover,
                showsReaderStylePopover: $showsReaderStylePopover,
                showsPageViewsPopover: $showsPageViewsPopover
            )
        }
        .background {
            FixedWindowToolbarPolicy()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .environment(\.workspaceOpenWindowHandler, openWindowHandler)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            openWindowHandler.update(action: openWindow)
        }
        .onChange(of: appState.currentArticle?.id) { _, _ in
            showsSavePopover = false
            showsReaderStylePopover = false
            showsPageViewsPopover = false
        }
        .onChange(of: appState.readerStylePresentationRequestID) { _, requestID in
            guard requestID != nil, appState.currentArticle != nil else { return }
            showsSavePopover = false
            showsPageViewsPopover = false
            showsReaderStylePopover = true
        }
        .onChange(of: appState.readerPageViewsPresentationRequestID) { _, requestID in
            guard requestID != nil, appState.currentArticle != nil else { return }
            showsSavePopover = false
            showsReaderStylePopover = false
            showsPageViewsPopover = true
        }
    }

    private func workspaceEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .defaultAppStorage(MacWikiDefaults.current)
            .environment(appState)
            .environment(\.modelContext, modelContext)
            .environment(\.workspaceOpenWindowHandler, openWindowHandler)
            .environment(\.openURL, openURL)
            .environment(\.macWikiAccessibilityPersonalization, accessibilityPersonalization)
    }

    private var directoryContentRevision: String {
        [
            selectedList?.id.uuidString ?? "",
            selectedLabel?.id.uuidString ?? "",
            selectedTag?.id.uuidString ?? "",
            String(describing: rootSelection),
            workspaceAppearanceRevision
        ].joined(separator: "|")
    }

    private var workspaceAppearanceRevision: String {
        [
            accessibilityPersonalization.reduceMotion ? "reduce-motion" : "motion",
            accessibilityPersonalization.reduceTransparency ? "opaque" : "transparent",
            accessibilityPersonalization.differentiateWithoutColor ? "differentiated" : "color",
            accessibilityPersonalization.colorSchemeContrast == .increased
                ? "high-contrast"
                : "standard-contrast"
        ].joined(separator: "|")
    }
}
