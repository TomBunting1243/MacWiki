import SwiftUI

struct DirectoryColumnView: View {
    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let sidebarSearchModel: SidebarSearchSurfaceModel
    let columnState: DirectoryColumnState
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        DirectoryView(
            selectedList: $selectedList,
            rootSelection: $rootSelection,
            selectedLabel: selectedLabel,
            selectedTag: selectedTag,
            sidebarSearchModel: sidebarSearchModel,
            columnState: columnState,
            onNewLabelWithArticle: onNewLabelWithArticle,
            onNewTagWithArticle: onNewTagWithArticle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
