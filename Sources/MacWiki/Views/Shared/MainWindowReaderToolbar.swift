import SwiftData
import SwiftUI

enum MainWindowReaderToolbarIdentifier {
    static let configuration = "main-window-native-toolbar-v1"
    static let navigation = "main-window.navigation"
    static let save = "main-window.save"
    static let readState = "main-window.read-state"
    static let find = "main-window.find"
    static let style = "main-window.style"
    static let pageViews = "main-window.page-views"
    static let openInBrowser = "main-window.open-in-browser"
    static let share = "main-window.share"
    static let inspector = "main-window.inspector"
}

/// The main window's Apple-owned toolbar. Commands span the window while tabs
/// remain scoped to the Reader detail column below it.
@MainActor
struct MainWindowReaderToolbar: CustomizableToolbarContent {
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
        ToolbarItem(id: MainWindowReaderToolbarIdentifier.navigation) {
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

        ToolbarSpacer(.fixed)

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.save) {
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
        }

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.readState) {
            Button(
                article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: article?.isRead == true ? "checkmark.circle.fill" : "circle"
            ) {
                toggleReadState()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.find) {
            Button("Find in Page", systemImage: "text.magnifyingglass") {
                appState.presentFindOnPage()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .accessibilityIdentifier("reader-find-in-page")
        }

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.style) {
            Button("Reader Style", systemImage: "textformat.size") {
                dismissOtherPopovers(keeping: .style)
                showsReaderStylePopover = true
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
            .popover(isPresented: $showsReaderStylePopover) {
                ReaderStylePopover()
            }
        }

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.pageViews) {
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
        }

        ToolbarSpacer(.flexible)

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.openInBrowser) {
            Button("Open in Browser", systemImage: "safari") {
                if let article {
                    openURL(article.url)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.share) {
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

        ToolbarItem(id: MainWindowReaderToolbarIdentifier.inspector) {
            Button(
                appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.trailing"
            ) {
                appState.toggleInspectorVisibility()
            }
            .labelStyle(.iconOnly)
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
