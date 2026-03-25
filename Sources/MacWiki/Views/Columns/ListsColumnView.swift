import SwiftUI

struct ListsColumnView: View {
    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarPaneBackground()
                .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])

            ListsSidebar(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: ColumnChromeMetrics.titlebarBandHeight)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 176, ideal: 220, max: 260)
    }
}
