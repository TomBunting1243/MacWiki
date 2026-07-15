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
            spaciousControls.id("reader-top-chrome-spacious")
            regularControls.id("reader-top-chrome-regular")
            compactControls.id("reader-top-chrome-compact")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .controlSize(.regular)
        .onChange(of: article?.id) { _, _ in
            showingSavePopover = false
            showingReaderStylePopover = false
            showingPageViewsPopover = false
        }
        .onChange(of: appState.readerStylePresentationRequestID) { _, requestID in
            guard requestID != nil, article != nil else { return }
            presentReaderStylePopover()
        }
        .onChange(of: appState.readerPageViewsPresentationRequestID) { _, requestID in
            guard requestID != nil, article != nil else { return }
            presentPageViewsPopover()
        }
    }

    private var spaciousControls: some View {
        HStack(spacing: 8) {
            navigationControls
            articleStateControls
            Spacer(minLength: 8)
            findButton
            readerPresentationControls
            externalControls
            inspectorButton
        }
    }

    private var regularControls: some View {
        HStack(spacing: 8) {
            navigationControls
            articleStateControls
            Spacer(minLength: 8)
            findButton
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
        NativeReaderToolbarButton(
            title: appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
            systemImage: "sidebar.trailing",
            accessibilityIdentifier: "reader-toggle-inspector",
            isEnabled: true,
            action: appState.toggleInspectorVisibility
        )
    }

    private var navigationControls: some View {
        HStack(spacing: 2) {
            NativeReaderToolbarButton(
                title: appState.listsSidebarVisible ? "Hide Lists" : "Show Lists",
                systemImage: "sidebar.leading",
                accessibilityIdentifier: "reader-toggle-lists",
                isEnabled: true,
                action: appState.toggleListsSidebarVisibility
            )

            NativeReaderToolbarButton(
                title: appState.directoryColumnVisible ? "Hide List Contents" : "Show List Contents",
                systemImage: "sidebar.squares.leading",
                accessibilityIdentifier: "reader-toggle-list-contents",
                isEnabled: true,
                action: appState.toggleDirectoryColumnVisibility
            )

            NativeReaderToolbarButton(
                title: "Back",
                systemImage: "chevron.left",
                accessibilityIdentifier: "reader-go-back",
                isEnabled: appState.currentTab?.canGoBack == true,
                action: appState.goBack
            )

            NativeReaderToolbarButton(
                title: "Forward",
                systemImage: "chevron.right",
                accessibilityIdentifier: "reader-go-forward",
                isEnabled: appState.currentTab?.canGoForward == true,
                action: appState.goForward
            )

            NativeReaderToolbarButton(
                title: "Search Wikipedia",
                systemImage: "magnifyingglass",
                accessibilityIdentifier: "reader-search-wikipedia",
                isEnabled: true
            ) {
                appState.startSearch(context: .navigation)
            }
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
            presentSavePopover()
        }
        .labelStyle(.iconOnly)
        .disabled(article == nil)
        .popover(isPresented: $showingSavePopover) {
            if let article {
                SaveToListPopover(article: article)
            }
        }
    }

    private var findButton: some View {
        NativeReaderToolbarButton(
            title: "Find in Page",
            systemImage: "text.magnifyingglass",
            accessibilityIdentifier: "reader-find-in-page",
            isEnabled: article != nil,
            action: presentFindOnPage
        )
    }

    private var readerPresentationControls: some View {
        ControlGroup {
            Button("Reader Style", systemImage: "textformat.size") {
                presentReaderStylePopover()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showingReaderStylePopover) {
                ReaderStylePopover()
            }

            Button("Page Views", systemImage: "chart.xyaxis.line") {
                presentPageViewsPopover()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showingPageViewsPopover) {
                pageViewsPopoverContent
            }
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
                    presentSavePopover()
                }
                .disabled(article == nil)

                Button(article?.isRead == true ? "Mark as Unread" : "Mark as Read") {
                    toggleReadState()
                }
                .disabled(article == nil)

                Divider()
            }

            Button("Find in Page", action: presentFindOnPage)
                .disabled(article == nil)
            Button("Reader Style") {
                presentReaderStylePopover()
            }
            .disabled(article == nil)
            Button("Page Views") {
                presentPageViewsPopover()
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
        .popover(isPresented: $showingSavePopover) {
            if let article {
                SaveToListPopover(article: article)
            }
        }
        .popover(isPresented: $showingReaderStylePopover) {
            ReaderStylePopover()
        }
        .popover(isPresented: $showingPageViewsPopover) {
            pageViewsPopoverContent
        }
    }

    @ViewBuilder
    private var pageViewsPopoverContent: some View {
        if let article {
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            )
        }
    }

    private func presentSavePopover() {
        showingReaderStylePopover = false
        showingPageViewsPopover = false
        showingSavePopover = true
    }

    private func presentReaderStylePopover() {
        showingSavePopover = false
        showingPageViewsPopover = false
        showingReaderStylePopover = true
    }

    private func presentPageViewsPopover() {
        showingSavePopover = false
        showingReaderStylePopover = false
        showingPageViewsPopover = true
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

    private func presentFindOnPage() {
        guard article != nil else { return }
        appState.presentFindOnPage()
    }
}
