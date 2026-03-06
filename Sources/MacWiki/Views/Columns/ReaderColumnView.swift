import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let tabBarLiquidGlass: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void

    private var topTabLaneHeight: CGFloat {
        ColumnChromeMetrics.topBarHeight
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
            .background {
                ColumnChromeBackground()
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                    .frame(height: 0.5)
                    .allowsHitTesting(false)
            }
        }
    }

    private var topTabLaneContent: some View {
        tabBarTop
        .frame(height: topTabLaneHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var tabBarTop: some View {
        TabBarView(chromeStyle: .toolbar, onNewLabelWithArticle: onNewLabelWithArticle)
    }

    private var tabBarStandalone: some View {
        TabBarView(chromeStyle: .standalone, onNewLabelWithArticle: onNewLabelWithArticle)
    }
}
