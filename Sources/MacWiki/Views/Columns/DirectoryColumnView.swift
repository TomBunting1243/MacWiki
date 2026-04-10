import SwiftUI

struct DirectoryColumnView: View {
    private enum Chrome {
        static let topInset: CGFloat = 0
    }

    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidebarPaneBackground()

            DirectoryView(
                selectedList: $selectedList,
                rootSelection: $rootSelection,
                selectedLabel: selectedLabel,
                selectedTag: selectedTag,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
            .padding(.top, Chrome.topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
    }
}
