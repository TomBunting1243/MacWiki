import SwiftUI
import SwiftData

private enum WindowCommandBarMetrics {
    static let height: CGFloat = 44
    static let groupHeight: CGFloat = 34
    static let buttonSize: CGFloat = 30
    static let horizontalPadding: CGFloat = 12
    static let groupInset: CGFloat = 4
    static let clusterSpacing: CGFloat = 10
    static let buttonSpacing: CGFloat = 1
}

struct MainWindowCommandBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @State private var showSavePopover = false
    @State private var showReaderStylePopover = false
    @State private var showStatsPopover = false

    private var currentTab: ArticleTab? {
        guard let activeId = appState.activeTabId else { return nil }
        return appState.openTabs.first(where: { $0.id == activeId })
    }

    private var currentArticle: Article? {
        appState.currentArticle
    }

    private var hasArticle: Bool {
        currentArticle != nil
    }

    private var principalTitle: String {
        if let article = currentArticle, !article.title.isEmpty {
            return article.title
        }

        if let tab = currentTab, !tab.isNewTab, !tab.article.title.isEmpty {
            return tab.article.title
        }

        if currentTab?.isNewTab == true {
            return "Discover"
        }

        return "MacWiki"
    }

    private var isRead: Bool {
        currentArticle?.isRead ?? false
    }

    private var isSavedInAnyList: Bool {
        guard let article = currentArticle else { return false }
        let normalized = ReadStateSync.normalizedTitle(article.title)
        return allLists.contains { list in
            list.articles.contains { ReadStateSync.normalizedTitle($0.title) == normalized }
        }
    }

    var body: some View {
        HStack(spacing: WindowCommandBarMetrics.clusterSpacing) {
            leadingCluster

            Spacer(minLength: WindowCommandBarMetrics.clusterSpacing)

            principalCluster

            Spacer(minLength: WindowCommandBarMetrics.clusterSpacing)

            trailingCluster
        }
        .padding(.horizontal, WindowCommandBarMetrics.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var leadingCluster: some View {
        commandCluster {
            iconButton(
                systemImage: "sidebar.leading",
                help: appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns",
                isDisabled: appState.isWikiHopNavigationLocked,
                action: toggleSidebar
            )

            iconButton(
                systemImage: "chevron.left",
                help: "Back",
                isDisabled: currentTab?.canGoBack != true,
                action: appState.goBack
            )

            iconButton(
                systemImage: "chevron.right",
                help: "Forward",
                isDisabled: currentTab?.canGoForward != true,
                action: appState.goForward
            )

            iconButton(
                systemImage: "magnifyingglass",
                help: "Search Wikipedia",
                isDisabled: appState.isWikiHopNavigationLocked || appState.isFocusModeEnabled,
                action: startSearch
            )

            iconButton(
                systemImage: "magnifyingglass.circle",
                help: "Find in Page",
                isDisabled: !hasArticle || appState.isFocusModeEnabled,
                action: toggleFindOnPage
            )
        }
    }

    private var principalCluster: some View {
        HStack(spacing: 8) {
            Text(principalTitle)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .allowsTightening(true)
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 118, maxWidth: 280)
        .frame(height: WindowCommandBarMetrics.groupHeight)
        .background {
            CommandBarPillBackground()
        }
        .help(principalTitle)
    }

    private var trailingCluster: some View {
        commandCluster {
            iconButton(
                systemImage: "plus",
                help: "New Tab",
                isDisabled: appState.isWikiHopNavigationLocked,
                action: appState.createNewTab
            )

            saveButton

            iconButton(
                systemImage: isRead ? "checkmark.circle.fill" : "circle",
                help: isRead ? "Mark as Unread" : "Mark as Read",
                isDisabled: !hasArticle,
                action: toggleRead
            )

            readerStyleButton

            shareButton

            moreMenu

            iconButton(
                systemImage: "sidebar.trailing",
                help: appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                isDisabled: appState.isFocusModeEnabled,
                action: toggleInspector
            )
        }
    }

    @ViewBuilder
    private func commandCluster<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: WindowCommandBarMetrics.buttonSpacing) {
            content()
        }
        .padding(.horizontal, WindowCommandBarMetrics.groupInset)
        .frame(height: WindowCommandBarMetrics.groupHeight)
        .background {
            CommandBarPillBackground()
        }
    }

    private func iconButton(
        systemImage: String,
        help: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            commandBarIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(help)
    }

    private func commandBarIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .regular))
            .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.92 : 0.82))
            .frame(width: WindowCommandBarMetrics.buttonSize, height: WindowCommandBarMetrics.buttonSize)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.clear)
            }
            .contentShape(Rectangle())
    }

    private var saveButton: some View {
        Button(action: presentSavePopover) {
            commandBarIcon(systemImage: isSavedInAnyList ? "bookmark.fill" : "bookmark")
        }
        .buttonStyle(.plain)
        .disabled(!hasArticle)
        .help("Save Article")
        .popover(isPresented: $showSavePopover, arrowEdge: .bottom) {
            if let article = currentArticle {
                SaveToListPopover(
                    articleTitle: article.title,
                    articleDescription: article.description,
                    articleExtract: article.extract,
                    thumbnailURL: article.thumbnailURL,
                    articleWordCount: article.wordCount
                )
            }
        }
    }

    private var readerStyleButton: some View {
        Button(action: presentReaderStylePopover) {
            commandBarIcon(systemImage: "textformat.size")
        }
        .buttonStyle(.plain)
        .help("Reader Style")
        .popover(isPresented: $showReaderStylePopover, arrowEdge: .bottom) {
            ReaderStylePopover()
        }
    }

    private var shareButton: some View {
        Group {
            if let articleURL = currentArticle?.url {
                ShareLink(item: articleURL) {
                    commandBarIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .help("Share")
            } else {
                Button(action: {}) {
                    commandBarIcon(systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
                .disabled(true)
                .help("Share")
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Open in Browser", systemImage: "safari", action: openCurrentArticleInBrowser)
                .disabled(!hasArticle)

            Button("Show Page Views", systemImage: "chart.xyaxis.line", action: presentStatsPopover)
                .disabled(!hasArticle)

            Button(
                appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
                systemImage: appState.isFocusModeEnabled ? "viewfinder.circle.fill" : "viewfinder.circle",
                action: toggleFocusMode
            )
            .disabled(appState.currentArticle == nil || appState.isWikiHopNavigationLocked)
        } label: {
            commandBarIcon(systemImage: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .help("More")
        .popover(isPresented: $showStatsPopover, arrowEdge: .bottom) {
            if let article = currentArticle {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: Date()
                )
            }
        }
    }

    private func toggleSidebar() {
        guard !appState.isWikiHopNavigationLocked else { return }
        withAnimation(ColumnMotion.sidebarVisibility) {
            appState.sidebarVisible.toggle()
        }
    }

    private func startSearch() {
        appState.startSearch(context: .navigation)
    }

    private func toggleFindOnPage() {
        guard hasArticle, let tabID = appState.activeTabId, !appState.isFocusModeEnabled else { return }

        if appState.showFindOnPage {
            appState.showFindOnPage = false
            appState.findOnPageQuery = ""
            appState.findOnPageMatchFound = nil
            appState.pendingFindOnPageRequest = AppState.FindOnPageRequest(
                requestID: UUID(),
                tabID: tabID,
                query: "",
                backwards: false
            )
        } else {
            appState.showFindOnPage = true
            appState.findOnPageMatchFound = nil
        }
    }

    private func presentSavePopover() {
        guard hasArticle else { return }
        showSavePopover = true
    }

    private func toggleRead() {
        guard let article = currentArticle else { return }
        let nextState = !isRead
        _ = ReadStateSync.applyReadState(nextState, for: article, in: modelContext, appState: appState)
    }

    private func presentReaderStylePopover() {
        showReaderStylePopover = true
    }

    private func openCurrentArticleInBrowser() {
        guard let article = currentArticle else { return }
        openURL(article.url)
    }

    private func presentStatsPopover() {
        guard hasArticle else { return }
        showStatsPopover = true
    }

    private func toggleFocusMode() {
        guard appState.currentArticle != nil else { return }
        appState.toggleFocusMode()
    }

    private func toggleInspector() {
        guard !appState.isFocusModeEnabled else { return }
        withAnimation(ColumnMotion.inspectorVisibility) {
            appState.toggleInspectorVisibility()
        }
    }
}

private struct CommandBarPillBackground: View {
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @Environment(\.colorScheme) private var colorScheme

    private var shape: some InsettableShape {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
    }

    var body: some View {
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(forceLegacyFallback: forceLegacyGlassFallback) {
            shape
                .fill(.clear)
                .glassEffect(.regular.interactive(false), in: shape)
                .overlay {
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.18 : 0.16)
                }
                .overlay {
                    shape
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.06), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.06), radius: 8, y: 1)
        } else {
            shape
                .fill(
                    Color(nsColor: .controlBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.82 : 0.88)
                )
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(colorScheme == .dark ? 0.10 : 0.03)
                }
                .overlay {
                    shape
                        .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.55)
                }
                .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.05), radius: 8, y: 1)
        }
    }
}
