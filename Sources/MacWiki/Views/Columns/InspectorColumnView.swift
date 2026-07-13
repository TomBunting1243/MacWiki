import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState

    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?

    var body: some View {
        InspectorPanel(
            showNewLabelSheet: $showNewLabelSheet,
            articleForNewLabel: $articleForNewLabel,
            currentArticleTitle: appState.currentArticle?.title
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}
