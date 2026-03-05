import SwiftUI

struct ReaderColumnView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    let tabBarLiquidGlass: Bool
    let onNewLabelWithArticle: (SavedArticle) -> Void

    /// Height reserved by titlebar/toolbar when full-size content is enabled.
    private var readerTopBarHeight: CGFloat {
        max(appState.windowTopObscuredHeight, ColumnChromeMetrics.titleBarClearance)
    }

    /// Additional spacer needed above custom reader chrome to avoid top clipping.
    private var readerTopSpacerHeight: CGFloat {
        max(0, readerTopBarHeight - ColumnChromeMetrics.topBarHeight)
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
                topToolbarLane
                topTabLane
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var topTabLane: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topTabLaneInset)
                .allowsHitTesting(false)

            tabBarTop
                .frame(height: ColumnChromeMetrics.topBarHeight)
        }
        .frame(height: topTabLaneHeight)
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

    private var topToolbarLane: some View {
        VStack(spacing: 0) {
            if readerTopSpacerHeight > 0 {
                Color.clear
                    .frame(height: readerTopSpacerHeight)
                    .allowsHitTesting(false)
            }

            ReaderToolbar()
                .frame(height: ColumnChromeMetrics.topBarHeight)
                .offset(y: ColumnChromeMetrics.readerToolbarOpticalYOffset)
                .frame(maxWidth: .infinity)
            .frame(height: ColumnChromeMetrics.topBarHeight)

            Color.clear
                .frame(height: ColumnChromeMetrics.readerTabToolbarGap)
                .allowsHitTesting(false)
        }
        .frame(height: readerTopSpacerHeight + ColumnChromeMetrics.topBarHeight + ColumnChromeMetrics.readerTabToolbarGap)
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

    private var topToolbarLaneSolid: some View {
        VStack(spacing: 0) {
            if readerTopSpacerHeight > 0 {
                Color.clear
                    .frame(height: readerTopSpacerHeight)
                    .allowsHitTesting(false)
            }

            ReaderToolbar()
                .frame(height: ColumnChromeMetrics.topBarHeight)
                .offset(y: ColumnChromeMetrics.readerToolbarOpticalYOffset)
                .frame(maxWidth: .infinity)
            .frame(height: ColumnChromeMetrics.topBarHeight)
        }
        .frame(height: readerTopSpacerHeight + ColumnChromeMetrics.topBarHeight)
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
