import AppKit
import SwiftData
import SwiftUI

struct ReaderToolbarEnvironment {
    let appState: AppState
    let modelContext: ModelContext
    let openURL: OpenURLAction
    let accessibilityPersonalization: MacWikiAccessibilityPersonalization

    init(
        appState: AppState,
        modelContext: ModelContext,
        openURL: OpenURLAction,
        accessibilityPersonalization: MacWikiAccessibilityPersonalization
    ) {
        self.appState = appState
        self.modelContext = modelContext
        self.openURL = openURL
        self.accessibilityPersonalization = accessibilityPersonalization
    }
}

/// AppKit owns the native toolbar and popover anchoring. The existing SwiftUI
/// popover content remains reusable and keeps its SwiftData/environment wiring.
@MainActor
final class ReaderToolbarPopoverPresenter: NSObject, NSPopoverDelegate {
    private enum Kind: Equatable {
        case save(articleID: String)
        case readerStyle
        case pageViews(articleID: String)

        var articleID: String? {
            switch self {
            case .save(let articleID), .pageViews(let articleID):
                articleID
            case .readerStyle:
                nil
            }
        }
    }

    var onClose: (() -> Void)?

    private var environment: ReaderToolbarEnvironment
    private var activePopover: NSPopover?
    private var activeKind: Kind?

    init(environment: ReaderToolbarEnvironment) {
        self.environment = environment
    }

    func update(environment: ReaderToolbarEnvironment) {
        self.environment = environment
    }

    func showSave(for article: Article, relativeTo item: NSToolbarItem) {
        show(
            SaveToListPopover(article: article),
            kind: .save(articleID: article.id),
            relativeTo: item
        )
    }

    func showReaderStyle(relativeTo item: NSToolbarItem) {
        show(
            ReaderStylePopover(),
            kind: .readerStyle,
            relativeTo: item
        )
    }

    func showReaderStyle(in window: NSWindow) {
        show(
            ReaderStylePopover(),
            kind: .readerStyle,
            in: window
        )
    }

    func showPageViews(for article: Article, relativeTo item: NSToolbarItem) {
        show(
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            ),
            kind: .pageViews(articleID: article.id),
            relativeTo: item
        )
    }

    func showPageViews(for article: Article, in window: NSWindow) {
        show(
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            ),
            kind: .pageViews(articleID: article.id),
            in: window
        )
    }

    func closeArticlePopoverIfArticleChanged(to articleID: String?) {
        guard let boundArticleID = activeKind?.articleID,
              boundArticleID != articleID else {
            return
        }
        activePopover?.close()
    }

    func close() {
        activePopover?.close()
        activePopover = nil
        activeKind = nil
    }

    func popoverDidClose(_ notification: Notification) {
        guard let closedPopover = notification.object as? NSPopover,
              closedPopover === activePopover else {
            return
        }
        activePopover = nil
        activeKind = nil
        onClose?()
    }

    private func show<Content: View>(
        _ content: Content,
        kind: Kind,
        relativeTo item: NSToolbarItem
    ) {
        activePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !environment.accessibilityPersonalization.reduceMotion
        popover.delegate = self
        popover.contentViewController = hostingController(for: content)

        activeKind = kind
        activePopover = popover
        popover.show(relativeTo: item)
    }

    private func show<Content: View>(
        _ content: Content,
        kind: Kind,
        in window: NSWindow
    ) {
        guard let contentView = window.contentView else { return }
        activePopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = !environment.accessibilityPersonalization.reduceMotion
        popover.delegate = self
        popover.contentViewController = hostingController(for: content)

        activeKind = kind
        activePopover = popover
        let anchor = NSRect(
            x: contentView.bounds.midX,
            y: contentView.bounds.maxY,
            width: 1,
            height: 1
        )
        popover.show(relativeTo: anchor, of: contentView, preferredEdge: .minY)
    }

    private func hostingController<Content: View>(for content: Content) -> NSViewController {
        let controller = NSHostingController(
            rootView: content
                .defaultAppStorage(MacWikiDefaults.current)
                .environment(environment.appState)
                .environment(\.modelContext, environment.modelContext)
                .environment(\.openURL, environment.openURL)
                .environment(
                    \.macWikiAccessibilityPersonalization,
                    environment.accessibilityPersonalization
                )
        )
        controller.sizingOptions = [.preferredContentSize]
        return controller
    }
}
