import SwiftData
import SwiftUI

struct MainWindowShell: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    @Binding var showNewLabelSheet: Bool
    @Binding var articleForNewLabel: SavedArticle?

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    @State private var showingSavePopover = false
    @State private var showingReaderStylePopover = false
    @State private var showingPageViewsPopover = false

    private var currentArticle: Article? {
        appState.currentArticle
    }

    private var currentTab: ArticleTab? {
        appState.currentTab
    }

    private var canToggleInspector: Bool {
        true
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

    private var inspectorPresented: Binding<Bool> {
        Binding(
            get: { appState.inspectorVisible },
            set: { appState.inspectorVisible = $0 }
        )
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView(columnVisibility: $appState.navigationSplitViewVisibility) {
            ListsColumnView(
                selectedList: $selectedList,
                selectedLabel: $selectedLabel,
                selectedTag: $selectedTag,
                rootSelection: $rootSelection,
                onEditLabel: onEditLabel,
                onAddNewLabel: onAddNewLabel
            )
        } content: {
            DirectoryColumnView(
                selectedList: $selectedList,
                rootSelection: $rootSelection,
                selectedLabel: selectedLabel,
                selectedTag: selectedTag,
                onNewLabelWithArticle: onNewLabelWithArticle,
                onNewTagWithArticle: onNewTagWithArticle
            )
        } detail: {
            ReaderColumnView(
                onNewLabelWithArticle: onNewLabelWithArticle
            )
            .environment(\.readerChromeMetrics, .hidden)
        }
        .inspector(isPresented: inspectorPresented) {
            InspectorColumnView(
                showNewLabelSheet: $showNewLabelSheet,
                articleForNewLabel: $articleForNewLabel
            )
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 340)
        }
        .toolbar {
            toolbarItems
        }
        .onChange(of: currentArticle?.id) { _, _ in
            showingSavePopover = false
            showingReaderStylePopover = false
            showingPageViewsPopover = false
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                appState.goBack()
            } label: {
                SwiftUI.Label("Back", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help("Back")
            .disabled(currentTab?.canGoBack != true)

            Button {
                appState.goForward()
            } label: {
                SwiftUI.Label("Forward", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .help("Forward")
            .disabled(currentTab?.canGoForward != true)
        }

        ToolbarItem(placement: .principal) {
            HStack(spacing: 14) {
                Button {
                    appState.startSearch(context: .navigation)
                } label: {
                    SwiftUI.Label("Search Wikipedia", systemImage: "magnifyingglass")
                }
                .labelStyle(.iconOnly)
                .help("Search Wikipedia")
                .disabled(!canSearch)

                Spacer(minLength: 24)

                HStack(spacing: 12) {
                    Button {
                        showingSavePopover = true
                    } label: {
                        SwiftUI.Label("Save Article", systemImage: "bookmark")
                    }
                    .labelStyle(.iconOnly)
                    .help("Save Article")
                    .disabled(!canActOnCurrentArticle)
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

                    Button {
                        toggleFindOnPage()
                    } label: {
                        SwiftUI.Label("Find in Page", systemImage: "magnifyingglass.circle")
                    }
                    .labelStyle(.iconOnly)
                    .help("Find in Page")
                    .disabled(!canFind)

                    Button {
                        showingReaderStylePopover = true
                    } label: {
                        SwiftUI.Label("Reader Style", systemImage: "textformat.size")
                    }
                    .labelStyle(.iconOnly)
                    .help("Reader Style")
                    .disabled(!canActOnCurrentArticle)
                    .popover(isPresented: $showingReaderStylePopover, arrowEdge: .bottom) {
                        ReaderStylePopover()
                            .environment(appState)
                    }

                    Button {
                        showingPageViewsPopover = true
                    } label: {
                        SwiftUI.Label("Show Page Views", systemImage: "chart.xyaxis.line")
                    }
                    .labelStyle(.iconOnly)
                    .help("Show Page Views")
                    .disabled(!canActOnCurrentArticle)
                    .popover(isPresented: $showingPageViewsPopover, arrowEdge: .bottom) {
                        if let article = currentArticle {
                            SidebarPageViewsPopoverContent(
                                title: article.title,
                                referenceDate: Date()
                            )
                            .environment(appState)
                        }
                    }

                    if let article = currentArticle {
                        ShareLink(item: article.url) {
                            SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .help("Share")
                    } else {
                        Button {
                        } label: {
                            SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .help("Share")
                        .disabled(true)
                    }

                    Menu {
                        Button(
                            currentArticle?.isRead == true ? "Mark as Unread" : "Mark as Read",
                            systemImage: currentArticle?.isRead == true ? "checkmark.circle.fill" : "circle"
                        ) {
                            toggleReadState()
                        }
                        .disabled(!canActOnCurrentArticle)

                        Button("Open in Browser", systemImage: "safari") {
                            openCurrentArticleInBrowser()
                        }
                        .disabled(!canActOnCurrentArticle)
                    } label: {
                        SwiftUI.Label("More", systemImage: "ellipsis.circle")
                    }
                    .labelStyle(.iconOnly)
                    .help("More")

                    Button {
                        appState.toggleInspectorVisibility()
                    } label: {
                        SwiftUI.Label("Toggle Inspector", systemImage: "sidebar.right")
                    }
                    .labelStyle(.iconOnly)
                    .help("Toggle Inspector")
                    .disabled(!canToggleInspector)
                }
            }
            .frame(minWidth: 520, idealWidth: 780, maxWidth: 940)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
