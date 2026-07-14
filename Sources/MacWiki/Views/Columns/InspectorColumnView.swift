import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        InspectorPanel(
            currentArticle: appState.currentArticle
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: .top)
    }
}
