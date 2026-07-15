import SwiftData
import SwiftUI

/// A stable reader-only toolbar for standalone article windows. History stays
/// leading while article actions and Inspector remain trailing.
@MainActor
struct ArticleWindowReaderToolbar: ToolbarContent {
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
        ToolbarItem {
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

        ToolbarSpacer(.flexible)

        ToolbarItem {
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

        ToolbarItem {
            Button(
                article?.isRead == true ? "Mark as Unread" : "Mark as Read",
                systemImage: article?.isRead == true ? "checkmark.circle.fill" : "circle"
            ) {
                toggleReadState()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem {
            Button("Find in Page", systemImage: "text.magnifyingglass") {
                appState.presentFindOnPage()
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem {
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

        ToolbarItem {
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

        ToolbarItem {
            Button("Open in Browser", systemImage: "safari") {
                if let article {
                    openURL(article.url)
                }
            }
            .labelStyle(.iconOnly)
            .disabled(article == nil)
        }

        ToolbarItem {
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

        ToolbarItem {
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
