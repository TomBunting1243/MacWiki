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

/// One native four-pane hierarchy keeps the reader and its WebView alive while
/// AppKit provides standard sidebar, content-list, and inspector behavior.
private struct MainWorkspaceShell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization) private var accessibilityPersonalization
    @AppStorage(AppStorageKey.MainWindow.sidebarWidth) private var sidebarWidth = AppStorageKey.MainWindow.sidebarWidthDefault
    @AppStorage(AppStorageKey.MainWindow.directoryWidth) private var directoryWidth = AppStorageKey.MainWindow.directoryWidthDefault
    @AppStorage(AppStorageKey.MainWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.MainWindow.inspectorWidthDefault
    @State private var openWindowHandler = WorkspaceOpenWindowHandler()

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

        NativeWorkspaceSplitView(
            sidebarVisible: $appState.listsSidebarVisible,
            directoryVisible: $appState.directoryColumnVisible,
            inspectorVisible: $appState.inspectorVisible,
            reduceMotion: accessibilityPersonalization.reduceMotion,
            initialSidebarWidth: CGFloat(sidebarWidth),
            initialDirectoryWidth: CGFloat(directoryWidth),
            initialInspectorWidth: CGFloat(inspectorWidth),
            sidebarRevision: workspaceAppearanceRevision,
            directoryRevision: directoryContentRevision,
            readerRevision: readerPresentationRevision,
            inspectorRevision: workspaceAppearanceRevision,
            readerChromeVisible: !appState.isWikiHopNavigationLocked,
            sidebar: workspaceEnvironment(
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
            readerTopAccessory: workspaceEnvironment(
                ReaderTopChromeView(
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            openWindowHandler.update(action: openWindow)
        }
    }

    private func workspaceEnvironment<Content: View>(_ content: Content) -> some View {
        content
            .defaultAppStorage(MacWikiDefaults.current)
            .environment(appState)
            .environment(\.modelContext, modelContext)
            .environment(\.workspaceOpenWindowHandler, openWindowHandler)
            .environment(\.openURL, openURL)
            .environment(\.colorScheme, colorScheme)
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
            colorScheme == .dark ? "dark" : "light",
            accessibilityPersonalization.reduceMotion ? "reduce-motion" : "motion",
            accessibilityPersonalization.reduceTransparency ? "opaque" : "transparent",
            accessibilityPersonalization.differentiateWithoutColor ? "differentiated" : "color",
            accessibilityPersonalization.colorSchemeContrast == .increased ? "high-contrast" : "standard-contrast"
        ].joined(separator: "|")
    }

    /// The Reader and its controls live in separate native hosting controllers.
    /// Include cross-host presentation signals in the bridge revision so an
    /// accessory action invalidates Reader chrome without changing the stable
    /// reader/WebView identity.
    private var readerPresentationRevision: String {
        [
            workspaceAppearanceRevision,
            appState.showFindOnPage ? "find-visible" : "find-hidden",
            appState.findOnPageFocusRequestID?.uuidString ?? ""
        ].joined(separator: "|")
    }
}
