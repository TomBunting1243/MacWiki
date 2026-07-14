import AppKit
import SwiftData
import SwiftUI

/// Routes menu-driven reader presentations to a standalone article window.
/// The native toolbar item is preferred as the popover anchor when the user
/// kept it visible; window content remains a reliable fallback after toolbar
/// customization or when the item has moved into overflow.
struct ArticleWindowReaderCommandPresenter: NSViewRepresentable {
    let appState: AppState
    let modelContext: ModelContext
    let openURL: OpenURLAction
    let accessibilityPersonalization: MacWikiAccessibilityPersonalization
    let readerStyleRequestID: UUID?
    let pageViewsRequestID: UUID?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        let environment = ReaderToolbarEnvironment(
            appState: appState,
            modelContext: modelContext,
            openURL: openURL,
            accessibilityPersonalization: accessibilityPersonalization
        )
        context.coordinator.update(
            environment: environment,
            window: view.window,
            readerStyleRequestID: readerStyleRequestID,
            pageViewsRequestID: pageViewsRequestID
        )
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.close()
    }

    @MainActor
    final class Coordinator {
        private var presenter: ReaderToolbarPopoverPresenter?
        private var lastReaderStyleRequestID: UUID?
        private var lastPageViewsRequestID: UUID?

        func update(
            environment: ReaderToolbarEnvironment,
            window: NSWindow?,
            readerStyleRequestID: UUID?,
            pageViewsRequestID: UUID?
        ) {
            let presenter = resolvedPresenter(environment: environment)
            guard let window else { return }

            if readerStyleRequestID != lastReaderStyleRequestID,
               readerStyleRequestID != nil {
                showReaderStyle(using: presenter, in: window)
            }
            if pageViewsRequestID != lastPageViewsRequestID,
               pageViewsRequestID != nil,
               let article = environment.appState.currentArticle {
                showPageViews(for: article, using: presenter, in: window)
            }

            lastReaderStyleRequestID = readerStyleRequestID
            lastPageViewsRequestID = pageViewsRequestID
        }

        func close() {
            presenter?.close()
            presenter = nil
        }

        private func resolvedPresenter(
            environment: ReaderToolbarEnvironment
        ) -> ReaderToolbarPopoverPresenter {
            if let presenter {
                presenter.update(environment: environment)
                return presenter
            }
            let presenter = ReaderToolbarPopoverPresenter(environment: environment)
            self.presenter = presenter
            return presenter
        }

        private func visibleItem(
            _ rawIdentifier: String,
            in window: NSWindow
        ) -> NSToolbarItem? {
            window.toolbar?.visibleItems?.first {
                $0.itemIdentifier.rawValue == rawIdentifier
            }
        }

        private func showReaderStyle(
            using presenter: ReaderToolbarPopoverPresenter,
            in window: NSWindow
        ) {
            if let item = visibleItem(ArticleWindowReaderToolbarIdentifier.style, in: window) {
                presenter.showReaderStyle(relativeTo: item)
            } else {
                presenter.showReaderStyle(in: window)
            }
        }

        private func showPageViews(
            for article: Article,
            using presenter: ReaderToolbarPopoverPresenter,
            in window: NSWindow
        ) {
            if let item = visibleItem(ArticleWindowReaderToolbarIdentifier.pageViews, in: window) {
                presenter.showPageViews(for: article, relativeTo: item)
            } else {
                presenter.showPageViews(for: article, in: window)
            }
        }
    }
}
