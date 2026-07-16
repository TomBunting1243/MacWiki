import SwiftUI

struct InspectorColumnView: View {
    @Environment(AppState.self) private var appState
    var includesHeader = true

    var body: some View {
        InspectorPanel(
            currentArticle: appState.currentArticle,
            includesHeader: includesHeader
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
