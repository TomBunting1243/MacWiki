import SwiftUI

struct ListsColumnView: View {
    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection

    let sidebarSearchModel: SidebarSearchSurfaceModel
    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    var body: some View {
        ListsSidebar(
            selectedList: $selectedList,
            selectedLabel: $selectedLabel,
            selectedTag: $selectedTag,
            rootSelection: $rootSelection,
            sidebarSearchModel: sidebarSearchModel,
            onEditLabel: onEditLabel,
            onAddNewLabel: onAddNewLabel
        )
        .ignoresSafeArea(.container, edges: [.top, .leading, .bottom])
    }
}
