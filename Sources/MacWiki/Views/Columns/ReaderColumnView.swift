import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    let onNewLabelWithArticle: (SavedArticle) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isWikiHopNavigationLocked {
                TabBarView(
                    chromeStyle: .strip,
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
            }

            ReaderView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
