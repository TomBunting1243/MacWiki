import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    let onNewLabelWithArticle: (SavedArticle) -> Void

    private var showsReaderChrome: Bool {
        !appState.isWikiHopNavigationLocked
    }

    private var readerChromeMetrics: ReaderChromeMetrics {
        guard showsReaderChrome else { return .hidden }
        return ReaderChromeMetrics(
            topObscuredHeight: ReaderTabLaneMetrics.height,
            topChromeVisible: true,
            titlebarTabStripVisible: true,
            titlebarTabStripHeight: ReaderTabLaneMetrics.height
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ReaderView()
                .environment(\.readerChromeMetrics, readerChromeMetrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsReaderChrome {
                TabBarView(
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
                .zIndex(2)
            }
        }
        .onChange(of: appState.activeTabId) { oldTabID, newTabID in
            appState.resetFindOnPageForTabChange(from: oldTabID, to: newTabID)
        }
    }

}
