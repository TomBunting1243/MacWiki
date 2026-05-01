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

    private enum Metrics {
        static let toolbarTopPadding: CGFloat = 7
        static let toolbarHeight: CGFloat = 52
        static let trafficLightColumnThreshold: CGFloat = 150
        static let trafficLightReservedWidth: CGFloat = 86
        static let trafficLightTrailingGap: CGFloat = 10
    }

    private enum ToolbarDensity: Equatable {
        case regular
        case compact
        case narrow

        init(width: CGFloat) {
            if width < 540 {
                self = .narrow
            } else if width < 780 {
                self = .compact
            } else {
                self = .regular
            }
        }

        var buttonSize: CGFloat {
            switch self {
            case .regular: return 34
            case .compact: return 31
            case .narrow: return 28
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .regular: return 20
            case .compact: return 12
            case .narrow: return 6
            }
        }

        var pillHorizontalPadding: CGFloat {
            switch self {
            case .regular: return 4
            case .compact: return 3
            case .narrow: return 2
            }
        }

        var pillVerticalPadding: CGFloat {
            switch self {
            case .regular, .compact: return 1
            case .narrow: return 0
            }
        }

        var pillSpacing: CGFloat {
            switch self {
            case .regular: return 2
            case .compact, .narrow: return 1
            }
        }

        var clusterSpacing: CGFloat {
            switch self {
            case .regular, .compact: return 10
            case .narrow: return 7
            }
        }

        var dividerHeight: CGFloat {
            switch self {
            case .regular: return 21
            case .compact: return 19
            case .narrow: return 16
            }
        }
    }

    private struct ToolbarVisibility: Equatable {
        var showsBackForward: Bool
        var showsReaderStyle: Bool
        var showsPageViews: Bool
        var showsOpenInBrowser: Bool
        var showsShare: Bool

        init(width: CGFloat) {
            showsBackForward = width >= 620
            showsReaderStyle = width >= 700
            showsShare = width >= 760
            showsPageViews = width >= 860
            showsOpenInBrowser = width >= 940
        }

        var hasOverflowActions: Bool {
            !showsBackForward ||
            !showsReaderStyle ||
            !showsPageViews ||
            !showsOpenInBrowser ||
            !showsShare
        }
    }

    private enum ReaderToolbarControl: Hashable {
        case listContents
        case back
        case forward
        case search
        case save
        case read
        case find
        case style
        case pageViews
        case openInBrowser
        case share
        case more
        case inspector
    }

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
            let density = ToolbarDensity(width: proxy.size.width)
            let visibility = ToolbarVisibility(width: proxy.size.width)

            toolbarContent(density: density, visibility: visibility)
                .padding(.leading, leadingPadding(density: density, proxy: proxy))
                .padding(.trailing, density.horizontalPadding)
                .padding(.top, Metrics.toolbarTopPadding)
                .animation(reduceMotion ? nil : ColumnMotion.readerOnlyVisibility, value: appState.sidebarVisible)
        }
        .frame(height: Metrics.toolbarHeight)
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
        density: ToolbarDensity,
        visibility: ToolbarVisibility
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

    private func listContentsPill(density: ToolbarDensity) -> some View {
        toolbarPill(density: density) {
            toolbarIconButton(
                .listContents,
                title: appState.sidebarVisible ? "Hide Sidebar and List Contents" : "Show Sidebar and List Contents",
                systemImage: "sidebar.leading",
                isEnabled: !appState.isWikiHopNavigationLocked,
                density: density
            ) {
                toggleListContentsVisibility()
            }
        }
    }

    private func navigationSearchPill(
        density: ToolbarDensity,
        visibility: ToolbarVisibility
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
    private func articleStatePill(density: ToolbarDensity) -> some View {
        toolbarPill(density: density) {
            articleStateControls(density: density)
        }
    }

    @ViewBuilder
    private func articleStateControls(density: ToolbarDensity) -> some View {
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
        density: ToolbarDensity,
        visibility: ToolbarVisibility
    ) -> some View {
        toolbarPill(density: density) {
            articleToolControls(density: density, visibility: visibility)
        }
    }

    @ViewBuilder
    private func articleToolControls(
        density: ToolbarDensity,
        visibility: ToolbarVisibility
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
        density: ToolbarDensity,
        visibility: ToolbarVisibility
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
                morePopover(visibility: visibility)
            }
        }
    }

    private func inspectorPill(density: ToolbarDensity) -> some View {
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
    private func openInBrowserControl(density: ToolbarDensity) -> some View {
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
    private func shareControl(density: ToolbarDensity) -> some View {
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

    private func morePopover(visibility: ToolbarVisibility) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !visibility.showsBackForward {
                morePopoverButton("Back", systemImage: "chevron.left", isEnabled: currentTab?.canGoBack == true) {
                    appState.goBack()
                }

                morePopoverButton("Forward", systemImage: "chevron.right", isEnabled: currentTab?.canGoForward == true) {
                    appState.goForward()
                }
            }

            if !visibility.showsReaderStyle {
                morePopoverButton("Reader Style", systemImage: "textformat.size", isEnabled: canActOnCurrentArticle) {
                    showingReaderStylePopover = true
                }
            }

            if !visibility.showsPageViews {
                morePopoverButton("Page Views", systemImage: "chart.xyaxis.line", isEnabled: canActOnCurrentArticle) {
                    showingPageViewsPopover = true
                }
            }

            if !visibility.showsOpenInBrowser {
                morePopoverButton("Open in Browser", systemImage: "safari", isEnabled: canActOnCurrentArticle) {
                    openCurrentArticleInBrowser()
                }
            }

            if !visibility.showsShare {
                if let article = currentArticle {
                    ShareLink(item: article.url) {
                        morePopoverLabel("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)
                } else {
                    morePopoverButton("Share", systemImage: "square.and.arrow.up", isEnabled: false) {
                    }
                }
            }

            if !visibility.hasOverflowActions {
                morePopoverButton("Open in Browser", systemImage: "safari", isEnabled: canActOnCurrentArticle) {
                    openCurrentArticleInBrowser()
                }
            }
        }
        .padding(8)
        .frame(width: 190)
    }

    private func morePopoverButton(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            showingMorePopover = false
            DispatchQueue.main.async {
                action()
            }
        } label: {
            morePopoverLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func morePopoverLabel(_ title: String, systemImage: String) -> some View {
        SwiftUI.Label(title, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private func toolbarPill<Content: View>(
        density: ToolbarDensity,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let pill = HStack(spacing: density.pillSpacing) {
            content()
        }
        .padding(.horizontal, density.pillHorizontalPadding)
        .padding(.vertical, density.pillVerticalPadding)

        if #available(macOS 26, *), usesNativeGlassToolbar {
            pill
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    toolbarPillStroke
                }
                .fixedSize()
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.10 : 0.026), radius: 7, x: 0, y: 3)
                .compositingGroup()
        } else {
            pill
                .background {
                    toolbarPillFallbackBackground
                }
                .fixedSize()
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.10 : 0.026), radius: 7, x: 0, y: 3)
                .compositingGroup()
        }
    }

    private func toolbarIconButton(
        _ control: ReaderToolbarControl,
        title: String,
        systemImage: String,
        isActive: Bool = false,
        isEnabled: Bool = true,
        density: ToolbarDensity,
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
        density: ToolbarDensity
    ) -> some View {
        let isHovered = hoveredControl == control
        let isInteractive = isEnabled && (isHovered || isActive)
        let label = ZStack {
            toolbarIconBackground(
                isHovered: isHovered,
                isActive: isActive,
                isEnabled: isEnabled
            )

            Image(systemName: systemImage)
                .font(.system(size: iconPointSize(for: density), weight: isActive ? .medium : .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(iconForeground(isHovered: isHovered, isActive: isActive, isEnabled: isEnabled))
        }
        .frame(width: density.buttonSize, height: density.buttonSize)
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .scaleEffect(isInteractive && !reduceMotion ? 1.012 : 1)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isActive)

        label
    }

    private func toolbarDivider(density: ToolbarDensity) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.050 : 0.034))
            .frame(width: 0.5, height: density.dividerHeight)
            .padding(.horizontal, 2)
    }

    @ViewBuilder
    private var toolbarPillFallbackBackground: some View {
        let darkMode = colorScheme == .dark
        let shape = Capsule(style: .continuous)
        if liquidGlassChrome {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.16 : 0.42))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(darkMode ? 0.074 : 0.056), lineWidth: 0.50)
                }
        } else {
            shape
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay {
                    shape.fill(Color(nsColor: .controlBackgroundColor).opacity(darkMode ? 0.11 : 0.065))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(darkMode ? 0.06 : 0.045), lineWidth: 0.44)
                }
        }
    }

    private var toolbarPillStroke: some View {
        Capsule(style: .continuous)
            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.056 : 0.038), lineWidth: 0.45)
    }

    private func toolbarIconBackground(
        isHovered: Bool,
        isActive: Bool,
        isEnabled: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let darkMode = colorScheme == .dark
        let fillOpacity: Double
        if !isEnabled {
            fillOpacity = 0
        } else if isActive {
            fillOpacity = darkMode ? 0.16 : 0.095
        } else if isHovered {
            fillOpacity = darkMode ? 0.14 : 0.075
        } else {
            fillOpacity = 0
        }

        return shape
            .fill(Color.primary.opacity(fillOpacity))
            .overlay {
                shape.strokeBorder(
                    Color.primary.opacity((isHovered || isActive) && isEnabled ? (darkMode ? 0.10 : 0.060) : 0),
                    lineWidth: 0.40
                )
            }
            .shadow(
                color: .black.opacity((isHovered || isActive) && isEnabled ? (darkMode ? 0.18 : 0.055) : 0),
                radius: 2,
                x: 0,
                y: 1
            )
            .padding(2)
    }

    private func iconForeground(isHovered: Bool, isActive: Bool, isEnabled: Bool) -> Color {
        let darkMode = colorScheme == .dark
        if !isEnabled {
            return Color.primary.opacity(darkMode ? 0.38 : 0.34)
        }
        if isActive {
            return Color.primary.opacity(darkMode ? 0.88 : 0.84)
        }
        if isHovered {
            return Color.primary.opacity(darkMode ? 0.90 : 0.86)
        }
        return Color.primary.opacity(darkMode ? 0.80 : 0.74)
    }

    private func iconPointSize(for density: ToolbarDensity) -> CGFloat {
        switch density {
        case .regular: return 15.5
        case .compact: return 14.5
        case .narrow: return 13.5
        }
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
            appState.toggleNavigationColumnsVisibility()
        } else {
            withAnimation(ColumnMotion.readerOnlyVisibility) {
                appState.toggleNavigationColumnsVisibility()
            }
        }
    }

    private func leadingPadding(density: ToolbarDensity, proxy: GeometryProxy) -> CGFloat {
        let minX = proxy.frame(in: .global).minX
        guard minX < Metrics.trafficLightColumnThreshold,
              proxy.safeAreaInsets.top > 0
        else {
            return density.horizontalPadding
        }

        let trafficLightClearance = Metrics.trafficLightReservedWidth - max(0, minX) + Metrics.trafficLightTrailingGap
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
