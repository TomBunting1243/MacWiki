import SwiftUI

struct DirectoryColumnView: View {
    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        DirectoryView(
            selectedList: $selectedList,
            rootSelection: $rootSelection,
            selectedLabel: selectedLabel,
            selectedTag: selectedTag,
            onNewLabelWithArticle: onNewLabelWithArticle,
            onNewTagWithArticle: onNewTagWithArticle
        )
        .navigationSplitViewColumnWidth(min: 196, ideal: 240, max: 320)
    }
}
