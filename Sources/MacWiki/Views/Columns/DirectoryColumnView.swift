import SwiftUI

struct DirectoryColumnView: View {
    private enum Chrome {
        static let topInset: CGFloat = 8
    }

    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let sidebarSearchModel: SidebarSearchSurfaceModel
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    var body: some View {
        DirectoryView(
            selectedList: $selectedList,
            rootSelection: $rootSelection,
            selectedLabel: selectedLabel,
            selectedTag: selectedTag,
            sidebarSearchModel: sidebarSearchModel,
            onNewLabelWithArticle: onNewLabelWithArticle,
            onNewTagWithArticle: onNewTagWithArticle
        )
        .padding(.top, Chrome.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            SidebarPaneBackground()
                .ignoresSafeArea(.container, edges: .top)
        }
    }
}
