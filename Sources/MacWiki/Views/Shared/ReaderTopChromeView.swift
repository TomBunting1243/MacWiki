import SwiftData
import SwiftUI

/// The main window's reader-only chrome. AppKit mounts this view in the
/// reader split item's native top accessory, rather than stretching controls
/// across navigation and inspector panes.
struct ReaderTopChromeView: View {
    @Environment(\.macWikiAccessibilityPersonalization.reduceTransparency) private var reduceTransparency
    let onNewLabelWithArticle: (SavedArticle) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ReaderToolbarAccessoryView()

            Divider()

            TabBarView(
                showsTopDivider: false,
                onNewLabelWithArticle: onNewLabelWithArticle
            )
        }
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                Color.clear
            }
        }
    }
}

private struct ReaderToolbarAccessoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @State private var showingSavePopover = false
    @State private var showingReaderStylePopover = false
    @State private var showingPageViewsPopover = false

    private var article: Article? {
        appState.currentArticle
    }

    private var currentArticleIsSaved: Bool {
        guard let article else { return false }
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        return allLists.contains { list in
            list.articles.contains {
                ReadStateSync.normalizedTitle($0.title) == normalizedTitle
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            spaciousControls
            regularControls
            compactControls
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .controlSize(.small)
        .onChange(of: article?.id) { _, _ in
            showingSavePopover = false
            showingReaderStylePopover = false
            showingPageViewsPopover = false
        }
        .onChange(of: appState.readerStylePresentationRequestID) { _, requestID in
            guard requestID != nil, article != nil else { return }
            showingReaderStylePopover = true
        }
        .onChange(of: appState.readerPageViewsPresentationRequestID) { _, requestID in
            guard requestID != nil, article != nil else { return }
            showingPageViewsPopover = true
        }
        .popover(isPresented: $showingSavePopover) {
            if let article {
                SaveToListPopover(article: article)
            }
        }
        .popover(isPresented: $showingReaderStylePopover) {
            ReaderStylePopover()
        }
        .popover(isPresented: $showingPageViewsPopover) {
            if let article {
                SidebarPageViewsPopoverContent(
                    title: article.title,
                    referenceDate: Date()
                )
            }
        }
    }

    private var spaciousControls: some View {
        HStack(spacing: 8) {
            navigationControls
            articleStateControls
            Spacer(minLength: 8)
            readerControls
            externalControls
            inspectorButton
        }
    }

    private var regularControls: some View {
        HStack(spacing: 8) {
            navigationControls
            articleStateControls
            Spacer(minLength: 8)
            Button("Find in Page", systemImage: "text.magnifyingglass", action: toggleFindOnPage)
                .labelStyle(.iconOnly)
                .disabled(article == nil)
                .help("Find in Page")
            moreMenu(includesArticleState: false)
            inspectorButton
        }
    }

    private var compactControls: some View {
        HStack(spacing: 8) {
            navigationControls
            Spacer(minLength: 4)
            moreMenu(includesArticleState: true)
            inspectorButton
        }
    }

    private var inspectorButton: some View {
        Button(
            appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
            systemImage: "sidebar.trailing"
        ) {
            appState.toggleInspectorVisibility()
        }
        .labelStyle(.iconOnly)
        .help(appState.inspectorVisible ? "Hide Inspector" : "Show Inspector")
    }

    private var navigationControls: some View {
        ControlGroup {
            Button(
                appState.listsSidebarVisible ? "Hide Lists" : "Show Lists",
                systemImage: "sidebar.leading"
            ) {
                appState.toggleListsSidebarVisibility()
            }
            .labelStyle(.iconOnly)

            Button(
                appState.directoryColumnVisible ? "Hide List Contents" : "Show List Contents",
                systemImage: "sidebar.squares.leading"
            ) {
                appState.toggleDirectoryColumnVisibility()
            }
            .labelStyle(.iconOnly)

            Button("Back", systemImage: "chevron.left") {
                appState.goBack()
            }
            .labelStyle(.iconOnly)
            .disabled(appState.currentTab?.canGoBack != true)

            Button("Forward", systemImage: "chevron.right") {
                appState.goForward()
            }
            .labelStyle(.iconOnly)
            .disabled(appState.currentTab?.canGoForward != true)

            Button("Search Wikipedia", systemImage: "magnifyingglass") {
                appState.startSearch(context: .navigation)
            }
            .labelStyle(.iconOnly)
        }
    }

    private var articleStateControls: some View {
        ControlGroup {
            saveButton

            Button(
                article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: article?.isRead == true ? "checkmark.circle.fill" : "circle"
            ) {
                toggleReadState()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }
    }

    private var saveButton: some View {
        Button(
            currentArticleIsSaved ? "Saved Article" : "Save Article",
            systemImage: currentArticleIsSaved ? "bookmark.fill" : "bookmark"
        ) {
            showingSavePopover = true
        }
        .labelStyle(.iconOnly)
        .disabled(article == nil)
    }

    private var readerControls: some View {
        ControlGroup {
            Button("Find in Page", systemImage: "text.magnifyingglass", action: toggleFindOnPage)
                .labelStyle(.iconOnly)
                .disabled(article == nil)

            Button("Reader Style", systemImage: "textformat.size") {
                showingReaderStylePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)

            Button("Page Views", systemImage: "chart.xyaxis.line") {
                showingPageViewsPopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }
    }

    private var externalControls: some View {
        ControlGroup {
            Button("Open in Browser", systemImage: "safari") {
                if let article {
                    openURL(article.url)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)

            if let article {
                ShareLink(item: article.url) {
                    SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                }
                .labelStyle(.iconOnly)
            } else {
                Button("Share", systemImage: "square.and.arrow.up") {}
                    .labelStyle(.iconOnly)
                    .disabled(true)
            }
        }
    }

    private func moreMenu(includesArticleState: Bool) -> some View {
        Menu("More Reader Actions", systemImage: "ellipsis.circle") {
            if includesArticleState {
                Button(currentArticleIsSaved ? "Saved Article" : "Save Article") {
                    showingSavePopover = true
                }
                .disabled(article == nil)

                Button(article?.isRead == true ? "Mark as Unread" : "Mark as Read") {
                    toggleReadState()
                }
                .disabled(article == nil)

                Divider()
            }

            Button("Find in Page", action: toggleFindOnPage)
                .disabled(article == nil)
            Button("Reader Style") {
                showingReaderStylePopover = true
            }
            .disabled(article == nil)
            Button("Page Views") {
                showingPageViewsPopover = true
            }
            .disabled(article == nil)

            Divider()

            Button("Open in Browser") {
                if let article {
                    openURL(article.url)
                }
            }
            .disabled(article == nil)

            if let article {
                ShareLink(item: article.url) {
                    SwiftUI.Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .menuStyle(.borderlessButton)
        .help("More Reader Actions")
    }

    private func toggleReadState() {
        guard let article else { return }
        _ = ReadStateSync.applyReadState(
            !article.isRead,
            for: article,
            in: modelContext,
            appState: appState
        )
    }

    private func toggleFindOnPage() {
        guard article != nil else { return }
        if appState.showFindOnPage,
           let tabID = appState.activeTabId {
            appState.dismissFindOnPage(
                activeTabID: tabID,
                clearsWebSelection: true
            )
        } else {
            appState.presentFindOnPage()
        }
    }
}
