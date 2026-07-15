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

/// The main window uses SwiftUI's platform-owned navigation and inspector
/// containers. This keeps collapse, resize, keyboard, and accessibility
/// behavior on the same native state path instead of mirroring it through a
/// custom AppKit split-controller bridge.
private struct MainWorkspaceShell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
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

        NavigationSplitView(columnVisibility: $appState.navigationSplitViewVisibility) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                sidebarSearchModel: sidebarSearchModel,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
            .navigationSplitViewColumnWidth(
                min: MainWindowColumnWidth.sidebarRange.lowerBound,
                ideal: CGFloat(sidebarWidth),
                max: MainWindowColumnWidth.sidebarRange.upperBound
            )
            .persistedColumnWidth(
                key: AppStorageKey.MainWindow.sidebarWidth,
                range: MainWindowColumnWidth.sidebarRange
            )
        } content: {
            DirectoryColumnView(
                selectedList: $selectedList,
                rootSelection: $rootSelection,
                selectedLabel: selectedLabel,
                selectedTag: selectedTag,
                sidebarSearchModel: sidebarSearchModel,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
            .navigationSplitViewColumnWidth(
                min: MainWindowColumnWidth.directoryRange.lowerBound,
                ideal: CGFloat(directoryWidth),
                max: MainWindowColumnWidth.directoryRange.upperBound
            )
            .persistedColumnWidth(
                key: AppStorageKey.MainWindow.directoryWidth,
                range: MainWindowColumnWidth.directoryRange
            )
        } detail: {
            VStack(spacing: 0) {
                TabBarView(
                    showsTopDivider: false,
                    onNewLabelWithArticle: onNewLabelWithArticle
                )

                Divider()

                ReaderColumnView()
                    .id("main-reader-column")
            }
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $appState.inspectorVisible) {
            InspectorColumnView()
                .inspectorColumnWidth(
                    min: MainWindowColumnWidth.inspectorRange.lowerBound,
                    ideal: CGFloat(inspectorWidth),
                    max: MainWindowColumnWidth.inspectorRange.upperBound
                )
                .persistedColumnWidth(
                    key: AppStorageKey.MainWindow.inspectorWidth,
                    range: MainWindowColumnWidth.inspectorRange
                )
        }
        // The toolbar has a Lists-specific native control. Remove SwiftUI's
        // automatic generic sidebar item so the window never exposes two
        // competing buttons for the same NavigationSplitView column.
        .toolbar(removing: .sidebarToggle)
        .toolbar(id: MainWindowReaderToolbarIdentifier.configuration) {
            MainWindowReaderToolbar(
                appState: appState,
                modelContext: modelContext,
                showsSavePopover: $showsSavePopover,
                showsReaderStylePopover: $showsReaderStylePopover,
                showsPageViewsPopover: $showsPageViewsPopover
            )
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
}
