import SwiftData
import SwiftUI
struct ReaderArticleToolbar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false

    @State private var showingSavePopover = false
    @State private var showingReaderStylePopover = false
    @State private var showingPageViewsPopover = false
    @State private var showingMorePopover = false
    @State private var hoveredControl: ReaderToolbarControl?
    private var usesNativeGlassToolbar: Bool {
        MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
        )
    }

    private var currentArticle: Article? {
        appState.currentArticle
    }
    private var currentTab: ArticleTab? {
        appState.currentTab
    }

    private var canSearch: Bool {
        !appState.isWikiHopNavigationLocked
    }
    private var canFind: Bool {
        currentArticle != nil
    }

    private var canActOnCurrentArticle: Bool {
        currentArticle != nil
    }
    private var currentArticleIsSaved: Bool {
        guard let currentArticle else { return false }
        let normalized = ReadStateSync.normalizedTitle(currentArticle.title)
        return allLists.contains { list in
            list.articles.contains {
                ReadStateSync.normalizedTitle($0.title) == normalized
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let density = ReaderToolbarDensity(width: proxy.size.width)
            let visibility = ReaderToolbarVisibility(width: proxy.size.width)
            toolbarContent(density: density, visibility: visibility)
                .padding(.leading, leadingPadding(density: density, proxy: proxy))
                .padding(.trailing, density.horizontalPadding)
                .padding(.top, ReaderToolbarMetrics.toolbarTopPadding)
                .animation(reduceMotion ? nil : ColumnMotion.readerOnlyVisibility, value: appState.directoryColumnVisible)
        }
        .frame(height: ReaderToolbarMetrics.toolbarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: currentArticle?.id) { _, _ in
            showingSavePopover = false
            showingReaderStylePopover = false
            showingPageViewsPopover = false
            showingMorePopover = false
        }
    }

    @ViewBuilder
    private func toolbarContent(
        density: ReaderToolbarDensity,
        visibility: ReaderToolbarVisibility
    ) -> some View {
        MacWikiGlassGroup(spacing: density.clusterSpacing) {
            HStack(spacing: density.clusterSpacing) {
                listContentsPill(density: density)

                navigationSearchPill(density: density, visibility: visibility)

                articleStatePill(density: density)

                Spacer(minLength: 16)

                articleToolsPill(density: density, visibility: visibility)

                shareBrowserOverflowPill(density: density, visibility: visibility)

                inspectorPill(density: density)
            }
            .frame(maxWidth: .infinity)
            .popover(isPresented: $showingReaderStylePopover, arrowEdge: .bottom) {
                ReaderStylePopover()
                    .environment(appState)
            }
            .popover(isPresented: $showingPageViewsPopover, arrowEdge: .bottom) {
                if let article = currentArticle {
                    SidebarPageViewsPopoverContent(
                        title: article.title,
                        referenceDate: Date()
                    )
                    .environment(appState)
                }
            }
        }
    }

    private func listContentsPill(density: ReaderToolbarDensity) -> some View {
        toolbarPill(density: density) {
            toolbarIconButton(
                .listContents,
                title: appState.directoryColumnVisible ? "Hide List Contents" : "Show List Contents",
                systemImage: "sidebar.squares.leading",
                isEnabled: !appState.isWikiHopNavigationLocked,
                density: density
            ) {
                toggleListContentsVisibility()
            }
        }
    }

    private func navigationSearchPill(
        density: ReaderToolbarDensity,
        visibility: ReaderToolbarVisibility
    ) -> some View {
        toolbarPill(density: density) {
            if visibility.showsBackForward {
                toolbarIconButton(
                    .back,
                    title: "Back",
                    systemImage: "chevron.left",
                    isEnabled: currentTab?.canGoBack == true,
                    density: density
                ) {
                    appState.goBack()
                }

                toolbarIconButton(
                    .forward,
                    title: "Forward",
                    systemImage: "chevron.right",
                    isEnabled: currentTab?.canGoForward == true,
                    density: density
                ) {
                    appState.goForward()
                }

                toolbarDivider(density: density)
            }

            toolbarIconButton(
                .search,
                title: "Search Wikipedia",
                systemImage: "magnifyingglass",
                isEnabled: canSearch,
                density: density
            ) {
                appState.startSearch(context: .navigation)
            }
        }
    }

    @ViewBuilder
    private func articleStatePill(density: ReaderToolbarDensity) -> some View {
        toolbarPill(density: density) {
            articleStateControls(density: density)
        }
    }

    @ViewBuilder
    private func articleStateControls(density: ReaderToolbarDensity) -> some View {
        toolbarIconButton(
            .save,
            title: currentArticleIsSaved ? "Saved Article" : "Save Article",
            systemImage: currentArticleIsSaved ? "bookmark.fill" : "bookmark",
            isActive: currentArticleIsSaved,
            isEnabled: canActOnCurrentArticle,
            density: density
        ) {
            showingSavePopover = true
        }
        .popover(isPresented: $showingSavePopover, arrowEdge: .bottom) {
            if let article = currentArticle {
                SaveToListPopover(
                    articleTitle: article.title,
                    articleDescription: article.description,
                    articleExtract: article.extract,
                    thumbnailURL: article.thumbnailURL,
                    articleWordCount: article.wordCount
                )
                .environment(appState)
                .environment(\.modelContext, modelContext)
            }
        }

        toolbarIconButton(
            .read,
            title: currentArticle?.isRead == true ? "Mark as Unread" : "Mark as Read",
            systemImage: currentArticle?.isRead == true ? "checkmark.circle.fill" : "circle",
            isActive: currentArticle?.isRead == true,
            isEnabled: canActOnCurrentArticle,
            density: density
        ) {
            toggleReadState()
        }
    }

    private func articleToolsPill(
        density: ReaderToolbarDensity,
        visibility: ReaderToolbarVisibility
    ) -> some View {
        toolbarPill(density: density) {
            articleToolControls(density: density, visibility: visibility)
        }
    }

    @ViewBuilder
    private func articleToolControls(
        density: ReaderToolbarDensity,
        visibility: ReaderToolbarVisibility
    ) -> some View {
        toolbarIconButton(
            .find,
            title: "Find in Page",
            systemImage: "magnifyingglass.circle",
            isEnabled: canFind,
            density: density
        ) {
            toggleFindOnPage()
        }

        if visibility.showsReaderStyle {
            toolbarIconButton(
                .style,
                title: "Reader Style",
                systemImage: "textformat.size",
                isEnabled: canActOnCurrentArticle,
                density: density
            ) {
                showingReaderStylePopover = true
            }
        }

        if visibility.showsPageViews {
            toolbarIconButton(
                .pageViews,
                title: "Show Page Views",
                systemImage: "chart.xyaxis.line",
                isEnabled: canActOnCurrentArticle,
                density: density
            ) {
                showingPageViewsPopover = true
            }
        }
    }

    private func shareBrowserOverflowPill(
        density: ReaderToolbarDensity,
        visibility: ReaderToolbarVisibility
    ) -> some View {
        toolbarPill(density: density) {
            if visibility.showsOpenInBrowser {
                openInBrowserControl(density: density)
            }

            if visibility.showsShare {
                shareControl(density: density)
            }

            toolbarIconButton(
                .more,
                title: visibility.hasOverflowActions ? "More" : "More Article Actions",
                systemImage: "ellipsis.circle",
                isEnabled: true,
                density: density
            ) {
                showingMorePopover = true
            }
            .popover(isPresented: $showingMorePopover, arrowEdge: .bottom) {
                ReaderToolbarOverflowPopover(
                    isPresented: $showingMorePopover,
                    visibility: visibility,
                    canGoBack: currentTab?.canGoBack == true,
                    canGoForward: currentTab?.canGoForward == true,
                    canActOnCurrentArticle: canActOnCurrentArticle,
                    articleURL: currentArticle?.url,
                    onBack: appState.goBack,
                    onForward: appState.goForward,
                    onReaderStyle: { showingReaderStylePopover = true },
                    onPageViews: { showingPageViewsPopover = true },
                    onOpenInBrowser: openCurrentArticleInBrowser
                )
            }
        }
    }

    private func inspectorPill(density: ReaderToolbarDensity) -> some View {
        toolbarPill(density: density) {
            toolbarIconButton(
                .inspector,
                title: appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.trailing",
                isEnabled: true,
                density: density
            ) {
                appState.toggleInspectorVisibility()
            }
        }
    }

    @ViewBuilder
    private func openInBrowserControl(density: ReaderToolbarDensity) -> some View {
        toolbarIconButton(
            .openInBrowser,
            title: "Open in Browser",
            systemImage: "safari",
            isEnabled: canActOnCurrentArticle,
            density: density
        ) {
            openCurrentArticleInBrowser()
        }
    }

    @ViewBuilder
    private func shareControl(density: ReaderToolbarDensity) -> some View {
        if let article = currentArticle {
            ShareLink(item: article.url) {
                toolbarIconLabel(
                    .share,
                    systemImage: "square.and.arrow.up",
                    isActive: false,
                    isEnabled: true,
                    density: density
                )
            }
            .buttonStyle(.plain)
            .help("Share")
            .accessibilityLabel("Share")
            .onHover { hovering in
                updateHover(.share, hovering: hovering, isEnabled: true)
            }
        } else {
            toolbarIconButton(
                .share,
                title: "Share",
                systemImage: "square.and.arrow.up",
                isEnabled: false,
                density: density
            ) {
            }
        }
    }

    @ViewBuilder
    private func toolbarPill<Content: View>(
        density: ReaderToolbarDensity,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ReaderToolbarPill(
            density: density,
            usesNativeGlass: usesNativeGlassToolbar,
            liquidGlassChrome: liquidGlassChrome
        ) {
            content()
        }
    }

    private func toolbarIconButton(
        _ control: ReaderToolbarControl,
        title: String,
        systemImage: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        density: ReaderToolbarDensity,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            toolbarIconLabel(
                control,
                systemImage: systemImage,
                isActive: isActive,
                isEnabled: isEnabled,
                density: density
            )
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .help(title)
        .accessibilityLabel(title)
        .onHover { hovering in
            updateHover(control, hovering: hovering, isEnabled: isEnabled)
        }
    }

    @ViewBuilder
    private func toolbarIconLabel(
        _ control: ReaderToolbarControl,
        systemImage: String,
        isActive: Bool,
        isEnabled: Bool,
        density: ReaderToolbarDensity
    ) -> some View {
        ReaderToolbarIconLabel(
            control: control,
            systemImage: systemImage,
            isActive: isActive,
            isEnabled: isEnabled,
            density: density,
            hoveredControl: hoveredControl
        )
    }

    private func toolbarDivider(density: ReaderToolbarDensity) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.050 : 0.034))
            .frame(width: 0.5, height: density.dividerHeight)
            .padding(.horizontal, 2)
    }

    private func updateHover(
        _ control: ReaderToolbarControl,
        hovering: Bool,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            if hovering {
                hoveredControl = control
            } else if hoveredControl == control {
                hoveredControl = nil
            }
        }
    }

    private func toggleListContentsVisibility() {
        if reduceMotion {
            appState.toggleDirectoryColumnVisibility()
        } else {
            withAnimation(ColumnMotion.readerOnlyVisibility) {
                appState.toggleDirectoryColumnVisibility()
            }
        }
    }

    private func leadingPadding(density: ReaderToolbarDensity, proxy: GeometryProxy) -> CGFloat {
        let minX = proxy.frame(in: .global).minX
        guard minX < ReaderToolbarMetrics.trafficLightColumnThreshold,
              proxy.safeAreaInsets.top > 0
        else {
            return density.horizontalPadding
        }

        let trafficLightClearance = ReaderToolbarMetrics.trafficLightReservedWidth
            - max(0, minX)
            + ReaderToolbarMetrics.trafficLightTrailingGap
        return max(density.horizontalPadding, trafficLightClearance)
    }

    private func toggleFindOnPage() {
        guard let tabID = appState.activeTabId, canFind else { return }

        if appState.showFindOnPage {
            let clearsWebSelection: Bool
            if #available(macOS 26, *) {
                clearsWebSelection = false
            } else {
                clearsWebSelection = true
            }
            appState.dismissFindOnPage(
                activeTabID: tabID,
                clearsWebSelection: clearsWebSelection
            )
            return
        }

        appState.presentFindOnPage()
    }

    private func toggleReadState() {
        guard let article = currentArticle else { return }
        let nextState = !article.isRead
        _ = ReadStateSync.applyReadState(
            nextState,
            for: article,
            in: modelContext,
            appState: appState
        )
    }

    private func openCurrentArticleInBrowser() {
        guard let article = currentArticle else { return }
        openURL(article.url)
    }
}
