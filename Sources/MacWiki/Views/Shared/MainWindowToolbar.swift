import SwiftUI
import SwiftData

struct MainWindowToolbar: ToolbarContent {
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

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(
                appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns",
                systemImage: "sidebar.leading",
                action: toggleSidebar
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked)
            .help(appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns")

            Button("Back", systemImage: "chevron.left", action: appState.goBack)
                .labelStyle(.iconOnly)
                .disabled(currentTab?.canGoBack != true)
                .help("Back")

            Button("Forward", systemImage: "chevron.right", action: appState.goForward)
                .labelStyle(.iconOnly)
                .disabled(currentTab?.canGoForward != true)
                .help("Forward")

            Button(
                "Search Wikipedia",
                systemImage: "magnifyingglass",
                action: startSearch
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked || appState.isFocusModeEnabled)
            .help("Search Wikipedia")

            Button(
                "Find in Page",
                systemImage: "magnifyingglass.circle",
                action: toggleFindOnPage
            )
            .labelStyle(.iconOnly)
            .disabled(!hasArticle || appState.isFocusModeEnabled)
            .help("Find in Page")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(
                "New Tab",
                systemImage: "plus",
                action: appState.createNewTab
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked)
            .help("New Tab")

            Button(
                isSavedInAnyList ? "Save Article" : "Save Article",
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

            Button(
                isRead ? "Mark as Unread" : "Mark as Read",
                systemImage: isRead ? "checkmark.circle.fill" : "circle",
                action: toggleRead
            )
            .labelStyle(.iconOnly)
            .disabled(!hasArticle)
            .help(isRead ? "Mark as Unread" : "Mark as Read")

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

            Button(
                "Open in Browser",
                systemImage: "safari",
                action: openCurrentArticleInBrowser
            )
            .labelStyle(.iconOnly)
            .disabled(!hasArticle)
            .help("Open in Browser")

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

            Button(
                appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
                systemImage: appState.isFocusModeEnabled ? "viewfinder.circle.fill" : "viewfinder.circle",
                action: toggleFocusMode
            )
            .labelStyle(.iconOnly)
            .disabled(appState.currentArticle == nil || appState.isWikiHopNavigationLocked)
            .help(appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode")

            Button(
                appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.trailing",
                action: toggleInspector
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isFocusModeEnabled)
            .help(appState.inspectorVisible ? "Hide Inspector" : "Show Inspector")
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
