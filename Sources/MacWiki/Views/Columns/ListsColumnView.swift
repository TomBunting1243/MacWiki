import SwiftUI

struct ListsColumnView: View {
    private enum Chrome {
        static let paneTopInset: CGFloat = 2
        static let contentTopInset: CGFloat = 8
        static let leadingInset: CGFloat = 8
        static let trailingInset: CGFloat = 10
        static let bottomInset: CGFloat = 8
    }

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            WorkspaceBackdropBackground()

            LeadingSidebarChromeMergeBackground()
                .padding(.top, Chrome.paneTopInset)
                .padding(.leading, Chrome.leadingInset)
                .padding(.trailing, Chrome.trailingInset)
                .padding(.bottom, Chrome.bottomInset)
                .ignoresSafeArea(.container, edges: .top)

            ListsSidebar(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
            .padding(.top, Chrome.contentTopInset)
            .padding(.leading, Chrome.leadingInset)
            .padding(.trailing, Chrome.trailingInset)
            .padding(.bottom, Chrome.bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationSplitViewColumnWidth(min: 188, ideal: 220, max: 280)
    }
}
