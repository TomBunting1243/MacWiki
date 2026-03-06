import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let tabBarLiquidGlass: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void

    /// Height reserved by the native titlebar/toolbar when full-size content is enabled.
    private var readerTopBarHeight: CGFloat {
        ColumnChromeMetrics.readerTitleBarHeight(windowTopObscuredHeight: appState.windowTopObscuredHeight)
    }

    private var topTabLaneHeight: CGFloat {
        ColumnChromeMetrics.topBarHeight
    }

    private var topTabLaneInset: CGFloat {
        0
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
                    topToolbarLaneSolid
                    if !appState.openTabs.isEmpty {
                        tabBarStandalone
                    }
                }
                ReaderView()
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }

    @ViewBuilder
    private var topChromeStack: some View {
        if shouldShowReaderTopChrome {
            VStack(spacing: 0) {
                nativeTitlebarSpacer
                topTabLaneContent
            }
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
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topTabLaneInset)
                .allowsHitTesting(false)

            tabBarTop
                .frame(height: ColumnChromeMetrics.topBarHeight)
        }
        .frame(height: topTabLaneHeight)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.internalDividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
    }

    private var nativeTitlebarSpacer: some View {
        WindowDragHandle(minLength: 180)
            .frame(height: readerTopBarHeight)
    }

    private var topToolbarLaneSolid: some View {
        nativeTitlebarSpacer
            .frame(height: readerTopBarHeight)
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.26 : 0.16)
                }
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
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
