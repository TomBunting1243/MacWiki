import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let tabBarLiquidGlass: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void

    private var topTabLaneHeight: CGFloat {
        ColumnChromeMetrics.topBarHeight
    }

    private var titlebarUnderlapHeight: CGFloat {
        ColumnChromeMetrics.titlebarBandHeight(
            windowTopObscuredHeight: appState.windowTopObscuredHeight
        )
    }

    private var shouldShowReaderTopChrome: Bool {
        !appState.isWikiHopNavigationLocked && !appState.isFocusModeEnabled
    }

    var body: some View {
        if tabBarLiquidGlass {
            ZStack(alignment: .top) {
                ReaderView()
                topChromeStack
            }
            .ignoresSafeArea(.container, edges: .top)
        } else {
            VStack(spacing: 0) {
                if shouldShowReaderTopChrome {
                    tabBarStandalone
                }
                ReaderView()
            }
        }
    }

    @ViewBuilder
    private var topChromeStack: some View {
        if shouldShowReaderTopChrome {
            topTabLaneContent
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(
                    .top,
                    titlebarUnderlapHeight +
                    ColumnChromeMetrics.commandBarTopGap +
                    ColumnChromeMetrics.commandBarHeight
                )
        }
    }

    private var topTabLaneContent: some View {
        tabBarTop
            .frame(height: topTabLaneHeight)
    }

    private var tabBarTop: some View {
        TabBarView(chromeStyle: .toolbar, onNewLabelWithArticle: onNewLabelWithArticle)
    }

    private var tabBarStandalone: some View {
        TabBarView(chromeStyle: .standalone, onNewLabelWithArticle: onNewLabelWithArticle)
    }
}
