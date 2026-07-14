import SwiftData
import SwiftUI

enum ArticleWindowReaderToolbarIdentifier {
    static let configuration = "article-window-reader-toolbar-v1"
    static let history = "article-window.history"
    static let save = "article-window.save"
    static let readState = "article-window.read-state"
    static let find = "article-window.find"
    static let style = "article-window.style"
    static let pageViews = "article-window.page-views"
    static let openInBrowser = "article-window.open-in-browser"
    static let share = "article-window.share"
    static let inspector = "article-window.inspector"
}

/// A reader-only customizable toolbar for standalone article windows. The main
/// window keeps its AppKit tracking-separator toolbar because it also owns four
/// pane boundaries; this surface has only reader actions plus its inspector.
@MainActor
struct ArticleWindowReaderToolbar: CustomizableToolbarContent {
    let appState: AppState
    let modelContext: ModelContext
    @Binding var showsSavePopover: Bool
    @Binding var showsReaderStylePopover: Bool
    @Binding var showsPageViewsPopover: Bool
    @Environment(\.openURL) private var openURL

    private var article: Article? {
        appState.currentArticle
    }

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.history) {
            ControlGroup("History") {
                Button("Back", systemImage: "chevron.left") {
                    appState.goBack()
                }
                .disabled(article == nil || !appState.canGoBack)

                Button("Forward", systemImage: "chevron.right") {
                    appState.goForward()
                }
                .disabled(article == nil || !appState.canGoForward)
            }
            .labelStyle(.iconOnly)
        }

        ToolbarSpacer(.fixed)

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.save) {
            Button("Save Article", systemImage: "bookmark") {
                showsSavePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsSavePopover) {
                if let article {
                    SaveToListPopover(article: article)
                }
            }
        }

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.readState) {
            Button(
                article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: article?.isRead == true ? "checkmark.circle.fill" : "circle"
            ) {
                toggleReadState()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.find) {
            Button("Find in Page", systemImage: "text.magnifyingglass") {
                appState.presentFindOnPage()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.style) {
            Button("Reader Style", systemImage: "textformat.size") {
                showsReaderStylePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsReaderStylePopover) {
                ReaderStylePopover()
            }
        }

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.pageViews) {
            Button("Page Views", systemImage: "chart.xyaxis.line") {
                showsPageViewsPopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsPageViewsPopover) {
                if let article {
                    SidebarPageViewsPopoverContent(
                        title: article.title,
                        referenceDate: Date()
                    )
                }
            }
        }

        ToolbarSpacer(.flexible)

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.openInBrowser) {
            Button("Open in Browser", systemImage: "safari") {
                if let article {
                    openURL(article.url)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.share) {
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

        ToolbarItem(id: ArticleWindowReaderToolbarIdentifier.inspector) {
            Button(
                appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.trailing"
            ) {
                appState.toggleInspectorVisibility()
            }
            .labelStyle(.iconOnly)
        }
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
}
