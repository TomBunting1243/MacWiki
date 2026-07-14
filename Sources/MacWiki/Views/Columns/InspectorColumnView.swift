import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        InspectorPanel(
            currentArticleTitle: appState.currentArticle?.title
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}
