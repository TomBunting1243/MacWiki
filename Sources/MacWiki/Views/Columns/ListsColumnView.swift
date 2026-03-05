import SwiftUI

struct ListsColumnView: View {
    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    let preferredWidth: CGFloat

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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 176, ideal: preferredWidth, max: 260)
    }
}
