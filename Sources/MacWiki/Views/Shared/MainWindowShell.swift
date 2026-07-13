import SwiftData
import SwiftUI

struct MainWindowShell: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKey.MainWindow.sidebarWidth) private var sidebarWidth = AppStorageKey.MainWindow.sidebarWidthDefault
    @AppStorage(AppStorageKey.MainWindow.directoryWidth) private var directoryWidth = AppStorageKey.MainWindow.directoryWidthDefault
    @AppStorage(AppStorageKey.MainWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.MainWindow.inspectorWidthDefault
    @State private var sidebarSearchModel = SidebarSearchSurfaceModel()

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        @Bindable var appState = appState

        GeometryReader { proxy in
            let responsiveInput = MainWindowResponsiveLayout.Input(
                windowWidth: proxy.size.width,
                sidebarVisible: appState.listsSidebarVisible,
                directoryVisible: appState.directoryColumnVisible,
                hasArticle: appState.currentArticle != nil,
                sidebarWidth: CGFloat(sidebarWidth),
                directoryWidth: CGFloat(directoryWidth),
                inspectorWidth: CGFloat(inspectorWidth)
            )

            MainNavigationShell(
                columnVisibility: $appState.navigationSplitViewVisibility,
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
            .inspector(isPresented: $appState.inspectorPresented) {
                MainInspectorColumn(
                    showNewLabelSheet: $showNewLabelSheet,
                    articleForNewLabel: $articleForNewLabel
                )
            }
            .onAppear {
                updateInspectorAvailability(for: responsiveInput)
            }
            .onChange(of: responsiveInput) { _, newValue in
                updateInspectorAvailability(for: newValue)
            }
        }
    }

    private func updateInspectorAvailability(for input: MainWindowResponsiveLayout.Input) {
        let isAvailable = MainWindowResponsiveLayout.canPresentInspector(for: input)
        guard appState.inspectorPresentationAvailable != isAvailable else { return }
        appState.inspectorPresentationAvailable = isAvailable
    }
}

/// A stable native hierarchy keeps the reader and its WebView alive while the
/// user changes auxiliary columns. NavigationSplitView owns the true sidebar;
/// HSplitView owns the resizable List Contents and reader workspace.
private struct MainNavigationShell: View {
    @Environment(AppState.self) private var appState
    @AppStorage(AppStorageKey.MainWindow.directoryWidth) private var directoryWidth = AppStorageKey.MainWindow.directoryWidthDefault

    @Binding var columnVisibility: NavigationSplitViewVisibility
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
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                sidebarSearchModel: sidebarSearchModel,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
        } detail: {
            HSplitView {
                if appState.directoryColumnVisible {
                    DirectoryColumnView(
                        selectedList: $selectedList,
                        rootSelection: $rootSelection,
                        selectedLabel: selectedLabel,
                        selectedTag: selectedTag,
                        sidebarSearchModel: sidebarSearchModel,
                        onNewLabelWithArticle: onNewLabelWithArticle,
                        onNewTagWithArticle: onNewTagWithArticle
                    )
                    .frame(
                        minWidth: MainWindowColumnWidth.directoryRange.lowerBound,
                        idealWidth: CGFloat(directoryWidth),
                        maxWidth: MainWindowColumnWidth.directoryRange.upperBound
                    )
                }

                ReaderColumnView(onNewLabelWithArticle: onNewLabelWithArticle)
                    .environment(\.readerChromeMetrics, .hidden)
                    .frame(
                        minWidth: MainWindowResponsiveLayout.minimumReaderWidth,
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
                    .id("main-reader-column")
            }
        }
    }
}

private struct MainInspectorColumn: View {
    @AppStorage(AppStorageKey.MainWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.MainWindow.inspectorWidthDefault

    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?

    var body: some View {
        InspectorColumnView(
            showNewLabelSheet: $showNewLabelSheet,
            articleForNewLabel: $articleForNewLabel
        )
        .frame(
            minWidth: MainWindowColumnWidth.inspectorRange.lowerBound,
            idealWidth: CGFloat(inspectorWidth),
            maxWidth: MainWindowColumnWidth.inspectorRange.upperBound
        )
        .persistedColumnWidth(
            key: AppStorageKey.MainWindow.inspectorWidth,
            range: MainWindowColumnWidth.inspectorRange
        )
    }
}
