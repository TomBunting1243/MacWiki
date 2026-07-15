import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        ReaderView()
            .environment(\.readerChromeMetrics, .hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: appState.activeTabId) { oldTabID, newTabID in
                appState.resetFindOnPageForTabChange(from: oldTabID, to: newTabID)
            }
    }
}
