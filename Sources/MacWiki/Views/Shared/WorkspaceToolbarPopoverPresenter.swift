import AppKit
import SwiftUI

/// Owns the one transient toolbar popover allowed at a time. Keeping this
/// presentation lifecycle outside the toolbar delegate makes exclusivity and
/// article-change dismissal independent of toolbar item construction.
@MainActor
final class WorkspaceToolbarPopoverPresenter: NSObject, NSPopoverDelegate {
    enum Kind {
        case save
        case readerStyle
        case pageViews
    }

    private var activePopover: NSPopover?

    func present(
        _ kind: Kind,
        relativeTo item: NSToolbarItem,
        configuration: WorkspaceToolbarConfiguration
    ) {
        let rootView: AnyView
        switch kind {
        case .save:
            guard let article = configuration.appState.currentArticle else { return }
            rootView = AnyView(
                SaveToListPopover(article: article)
                    .defaultAppStorage(MacWikiDefaults.current)
                    .environment(configuration.appState)
                    .environment(\.modelContext, configuration.modelContext)
            )
        case .readerStyle:
            rootView = AnyView(
                ReaderStylePopover()
                    .defaultAppStorage(MacWikiDefaults.current)
                    .environment(configuration.appState)
            )
        case .pageViews:
            guard let title = configuration.snapshot.articleTitle else { return }
            rootView = AnyView(
                SidebarPageViewsPopoverContent(
                    title: title,
                    referenceDate: Date()
                )
                .defaultAppStorage(MacWikiDefaults.current)
                .environment(configuration.appState)
            )
        }

        close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: rootView)
        activePopover = popover
        popover.show(relativeTo: item)
    }

    func close() {
        let popover = activePopover
        activePopover = nil
        popover?.delegate = nil
        popover?.close()
    }

    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover,
              popover === activePopover else {
            return
        }
        popover.delegate = nil
        activePopover = nil
    }
}
