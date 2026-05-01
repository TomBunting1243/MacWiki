import SwiftData
import SwiftUI

struct MainWindowShell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(AppStorageKey.MainWindow.sidebarWidth) private var sidebarWidth = AppStorageKey.MainWindow.sidebarWidthDefault
    @AppStorage(AppStorageKey.MainWindow.inspectorWidth) private var inspectorWidth = AppStorageKey.MainWindow.inspectorWidthDefault

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

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { appState.inspectorVisible },
            set: { appState.inspectorVisible = $0 }
        )
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            if appState.directoryColumnVisible {
                navigationShell(columnVisibility: $appState.navigationSplitViewVisibility)
                    .transition(shellTransition)
                    .zIndex(1)
            } else if appState.listsSidebarVisible {
                sidebarReaderShell
                    .transition(shellTransition)
                    .zIndex(2)
            } else {
                readerOnlyShell
                    .transition(shellTransition)
                    .zIndex(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(shellAnimation, value: appState.directoryColumnVisible)
        .animation(shellAnimation, value: appState.listsSidebarVisible)
        .inspector(isPresented: inspectorPresented) {
            inspectorColumn
        }
    }

    private var shellAnimation: Animation? {
        reduceMotion ? nil : ColumnMotion.readerOnlyVisibility
    }

    private var shellTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }

        return .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.996, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.002, anchor: .center))
        )
    }

    private func navigationShell(columnVisibility: Binding<NavigationSplitViewVisibility>) -> some View {
        NavigationSplitView(columnVisibility: columnVisibility) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
        } content: {
            DirectoryColumnView(
                selectedList: $selectedList,
                rootSelection: $rootSelection,
                selectedLabel: selectedLabel,
                selectedTag: selectedTag,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
        } detail: {
            ReaderColumnView(
                onNewLabelWithArticle: onNewLabelWithArticle
            )
            .environment(\.readerChromeMetrics, .hidden)
        }
    }

    private var sidebarReaderShell: some View {
        HStack(spacing: 0) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
            .frame(
                minWidth: MainWindowColumnWidth.sidebarRange.lowerBound,
                idealWidth: CGFloat(sidebarWidth),
                maxWidth: MainWindowColumnWidth.sidebarRange.upperBound
            )

            Divider()

            ReaderColumnView(
                onNewLabelWithArticle: onNewLabelWithArticle
            )
            .environment(\.readerChromeMetrics, .hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var readerOnlyShell: some View {
        ReaderColumnView(
            onNewLabelWithArticle: onNewLabelWithArticle
        )
        .environment(\.readerChromeMetrics, .hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var inspectorColumn: some View {
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
