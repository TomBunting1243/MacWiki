import SwiftUI
import SwiftData

struct MainWindowToolbar: CustomizableToolbarContent {
    private enum ItemID {
        static let sidebar = "sidebar"
        static let back = "back"
        static let forward = "forward"
        static let search = "search"
        static let find = "find"
        static let principal = "principal"
        static let newTab = "new-tab"
        static let save = "save"
        static let markRead = "mark-read"
        static let readerStyle = "reader-style"
        static let share = "share"
        static let browser = "browser"
        static let pageViews = "page-views"
        static let focus = "focus"
        static let inspector = "inspector"
    }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
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

    private var showsDiscoverIdentity: Bool {
        currentTab?.isNewTab == true && currentArticle == nil
    }

    private var principalTitle: String {
        if let article = currentArticle, !article.title.isEmpty {
            return article.title
        }

        if showsDiscoverIdentity {
            return "Discover"
        }

        if let tab = currentTab, !tab.isNewTab, !tab.article.title.isEmpty {
            return tab.article.title
        }

        return "MacWiki"
    }

    private var principalSubtitle: String? {
        guard showsDiscoverIdentity else { return nil }
        return "Today’s Edition"
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

    var body: some CustomizableToolbarContent {
        Group {
            ToolbarItem(id: ItemID.sidebar, placement: .navigation) {
                sidebarToggleButton
            }

            ToolbarItem(id: ItemID.back, placement: .navigation) {
                backButton
            }

            ToolbarItem(id: ItemID.forward, placement: .navigation) {
                forwardButton
            }

            ToolbarItem(id: ItemID.search, placement: .navigation) {
                searchButton
            }

            ToolbarItem(id: ItemID.find, placement: .navigation) {
                findButton
            }

            ToolbarItem(id: ItemID.principal, placement: .principal) {
                principalIdentityView
            }
            .customizationBehavior(.disabled)

            ToolbarItem(id: ItemID.newTab, placement: .primaryAction) {
                newTabButton
            }

            ToolbarItem(id: ItemID.save, placement: .primaryAction) {
                saveButton
            }
        }

        Group {
            ToolbarItem(id: ItemID.markRead, placement: .primaryAction) {
                markReadButton
            }

            ToolbarItem(id: ItemID.readerStyle, placement: .primaryAction) {
                readerStyleButton
            }

            ToolbarItem(id: ItemID.share, placement: .primaryAction) {
                shareButton
            }

            ToolbarItem(id: ItemID.browser, placement: .primaryAction) {
                browserButton
            }
            .defaultCustomization(.hidden)

            ToolbarItem(id: ItemID.pageViews, placement: .primaryAction) {
                pageViewsButton
            }
            .defaultCustomization(.hidden)

            ToolbarItem(id: ItemID.focus, placement: .primaryAction) {
                focusButton
            }
            .defaultCustomization(.hidden)

            ToolbarItem(id: ItemID.inspector, placement: .primaryAction) {
                inspectorButton
            }
        }
    }

    private var sidebarToggleButton: some View {
        Button(
            appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns",
            systemImage: "sidebar.leading",
            action: toggleSidebar
        )
        .labelStyle(.iconOnly)
        .disabled(appState.isWikiHopNavigationLocked)
        .help(appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns")
    }

    private var backButton: some View {
        Button("Back", systemImage: "chevron.left", action: appState.goBack)
            .labelStyle(.iconOnly)
            .disabled(currentTab?.canGoBack != true)
            .help("Back")
    }

    private var forwardButton: some View {
        Button("Forward", systemImage: "chevron.right", action: appState.goForward)
            .labelStyle(.iconOnly)
            .disabled(currentTab?.canGoForward != true)
            .help("Forward")
    }

    private var searchButton: some View {
        Button(
            "Search Wikipedia",
            systemImage: "magnifyingglass",
            action: startSearch
        )
        .labelStyle(.iconOnly)
        .disabled(appState.isWikiHopNavigationLocked || appState.isFocusModeEnabled)
        .help("Search Wikipedia")
    }

    private var findButton: some View {
        Button(
            "Find in Page",
            systemImage: "magnifyingglass.circle",
            action: toggleFindOnPage
        )
        .labelStyle(.iconOnly)
        .disabled(!hasArticle || appState.isFocusModeEnabled)
        .help("Find in Page")
    }

    private var newTabButton: some View {
        Button(
            "New Tab",
            systemImage: "plus",
            action: appState.createNewTab
        )
        .labelStyle(.iconOnly)
        .disabled(appState.isWikiHopNavigationLocked)
        .help("New Tab")
    }

    private var saveButton: some View {
        Button(
            "Save Article",
            systemImage: isSavedInAnyList ? "bookmark.fill" : "bookmark",
            action: presentSavePopover
        )
        .labelStyle(.iconOnly)
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

    private var principalIdentityView: some View {
        VStack(spacing: 1) {
            Text(principalTitle)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            if let subtitle = principalSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .allowsTightening(true)
        .padding(.horizontal, 6)
        .help(principalTitle)
    }

    private var markReadButton: some View {
        Button(
            isRead ? "Mark as Unread" : "Mark as Read",
            systemImage: isRead ? "checkmark.circle.fill" : "circle",
            action: toggleRead
        )
        .labelStyle(.iconOnly)
        .disabled(!hasArticle)
        .help(isRead ? "Mark as Unread" : "Mark as Read")
    }

    private var readerStyleButton: some View {
        Button(
            "Reader Style",
            systemImage: "textformat.size",
            action: presentReaderStylePopover
        )
        .labelStyle(.iconOnly)
        .help("Reader Style")
        .popover(isPresented: $showReaderStylePopover, arrowEdge: .bottom) {
            ReaderStylePopover()
        }
    }

    private var shareButton: some View {
        Group {
            if let articleURL = currentArticle?.url {
                ShareLink(item: articleURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Share")
            } else {
                Button("Share", systemImage: "square.and.arrow.up") {}
                    .labelStyle(.iconOnly)
                    .disabled(true)
                    .help("Share")
            }
        }
    }

    private var browserButton: some View {
        Button(
            "Open in Browser",
            systemImage: "safari",
            action: openCurrentArticleInBrowser
        )
        .labelStyle(.iconOnly)
        .disabled(!hasArticle)
        .help("Open in Browser")
    }

    private var pageViewsButton: some View {
        Button(
            "Show Page Views",
            systemImage: "chart.xyaxis.line",
            action: presentStatsPopover
        )
        .labelStyle(.iconOnly)
        .disabled(!hasArticle)
        .help("Show Page Views")
        .popover(isPresented: $showStatsPopover, arrowEdge: .bottom) {
            if let article = currentArticle {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: Date()
                )
            }
        }
    }

    private var focusButton: some View {
        Button(
            appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
            systemImage: appState.isFocusModeEnabled ? "viewfinder.circle.fill" : "viewfinder.circle",
            action: toggleFocusMode
        )
        .labelStyle(.iconOnly)
        .disabled(appState.currentArticle == nil || appState.isWikiHopNavigationLocked)
        .help(appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode")
    }

    private var inspectorButton: some View {
        Button(
            appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
            systemImage: "sidebar.trailing",
            action: toggleInspector
        )
        .labelStyle(.iconOnly)
        .disabled(appState.isFocusModeEnabled)
        .help(appState.inspectorVisible ? "Hide Inspector" : "Show Inspector")
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
