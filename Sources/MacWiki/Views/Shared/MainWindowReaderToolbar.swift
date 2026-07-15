import SwiftData
import SwiftUI

/// The main window's Apple-owned toolbar. Commands span the window while tabs
/// remain scoped to the Reader detail column below it.
@MainActor
struct MainWindowReaderToolbar: ToolbarContent {
    let appState: AppState
    let modelContext: ModelContext
    @Binding var showsSavePopover: Bool
    @Binding var showsReaderStylePopover: Bool
    @Binding var showsPageViewsPopover: Bool
    @Environment(\.openURL) private var openURL

    private var article: Article? {
        appState.currentArticle
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            ControlGroup("Navigation") {
                Button(
                    appState.directoryColumnVisible ? "Hide List Contents" : "Show List Contents",
                    systemImage: "sidebar.squares.leading"
                ) {
                    appState.toggleDirectoryColumnVisibility()
                }
                .disabled(appState.isWikiHopNavigationLocked)

                Button("Back", systemImage: "chevron.left") {
                    appState.goBack()
                }
                .disabled(article == nil || !appState.canGoBack)

                Button("Forward", systemImage: "chevron.right") {
                    appState.goForward()
                }
                .disabled(article == nil || !appState.canGoForward)

                Button("Search Wikipedia", systemImage: "magnifyingglass") {
                    appState.startSearch(context: .navigation)
                }
            }
            .labelStyle(.iconOnly)
        }

        // macOS owns the edge placement: navigation remains leading while the
        // complete Reader action set forms one stable trailing group.
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Save Article", systemImage: "bookmark") {
                dismissOtherPopovers(keeping: .save)
                showsSavePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsSavePopover) {
                if let article {
                    SaveToListPopover(article: article)
                }
            }

            Button(
                article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: article?.isRead == true ? "checkmark.circle.fill" : "circle"
            ) {
                toggleReadState()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)

            Button("Find in Page", systemImage: "text.magnifyingglass") {
                appState.presentFindOnPage()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .accessibilityIdentifier("reader-find-in-page")

            Button("Reader Style", systemImage: "textformat.size") {
                dismissOtherPopovers(keeping: .style)
                showsReaderStylePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsReaderStylePopover) {
                ReaderStylePopover()
            }

            Button("Page Views", systemImage: "chart.xyaxis.line") {
                dismissOtherPopovers(keeping: .pageViews)
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

    private enum PopoverKind {
        case save
        case style
        case pageViews
    }

    private func dismissOtherPopovers(keeping kind: PopoverKind) {
        if kind != .save { showsSavePopover = false }
        if kind != .style { showsReaderStylePopover = false }
        if kind != .pageViews { showsPageViewsPopover = false }
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
