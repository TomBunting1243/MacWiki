import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    let onNewLabelWithArticle: (SavedArticle) -> Void

    private enum Metrics {
        static let articleToolbarMaterialHeight: CGFloat = 54
        static let topChromeMaterialHeight = articleToolbarMaterialHeight + TabBarChromeStyle.strip.height
    }

    private var showsReaderChrome: Bool {
        !appState.isWikiHopNavigationLocked
    }

    private var readerChromeMetrics: ReaderChromeMetrics {
        guard showsReaderChrome else { return .hidden }
        return ReaderChromeMetrics(
            topObscuredHeight: TabBarChromeStyle.strip.height,
            topChromeVisible: true,
            titlebarTabStripVisible: true,
            titlebarTabStripHeight: TabBarChromeStyle.strip.height
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            ReaderView()
                .environment(\.readerChromeMetrics, readerChromeMetrics)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showsReaderChrome {
                readerTopChromeBackground
                    .zIndex(0.5)

                ReaderArticleToolbar()
                    .zIndex(2)

                TabBarView(
                    chromeStyle: .strip,
                    onNewLabelWithArticle: onNewLabelWithArticle
                )
                .zIndex(1)
            }
        }
    }

    private var readerTopChromeBackground: some View {
        ReaderTabLaneBackground()
            .frame(height: Metrics.topChromeMaterialHeight)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(.container, edges: .top)
            .allowsHitTesting(false)
    }
}
