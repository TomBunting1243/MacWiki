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
        max(appState.windowTopObscuredHeight, 0)
    }

    private var commandBarOffsetHeight: CGFloat {
        titlebarUnderlapHeight + ColumnChromeMetrics.commandBarHeight
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
                .padding(.top, commandBarOffsetHeight)
        }
    }

    private var topTabLaneContent: some View {
        tabBarTop
            .frame(height: topTabLaneHeight)
    }

    private var tabBarTop: some View {
        TabBarView(chromeStyle: .strip, onNewLabelWithArticle: onNewLabelWithArticle)
    }

    private var tabBarStandalone: some View {
        TabBarView(chromeStyle: .standalone, onNewLabelWithArticle: onNewLabelWithArticle)
    }
}
