import SwiftUI

struct ListsColumnView: View {
    @AppStorage(AppStorageKey.MainWindow.sidebarWidth) private var sidebarWidth = AppStorageKey.MainWindow.sidebarWidthDefault

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    var body: some View {
        ListsSidebar(
            selectedList: $selectedList,
            selectedLabel: $selectedLabel,
            selectedTag: $selectedTag,
            rootSelection: $rootSelection,
            onEditLabel: onEditLabel,
            onAddNewLabel: onAddNewLabel
        )
        .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
        .navigationSplitViewColumnWidth(
            min: MainWindowColumnWidth.sidebarRange.lowerBound,
            ideal: CGFloat(sidebarWidth),
            max: MainWindowColumnWidth.sidebarRange.upperBound
        )
        .persistedColumnWidth(
            key: AppStorageKey.MainWindow.sidebarWidth,
            range: MainWindowColumnWidth.sidebarRange
        )
    }
}
