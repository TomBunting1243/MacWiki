import AppKit
import Observation
import SwiftData
import SwiftUI

/// Owns the main window's native reader-scoped toolbar. AppKit is responsible
/// for pane tracking, customization, overflow, autosave, and native control
/// presentation; AppState remains the single source of truth for actions.
@MainActor
final class ReaderToolbarController: NSObject,
    NSToolbarDelegate,
    NSSharingServicePickerToolbarItemDelegate
{
    private struct Snapshot: Equatable {
        let articleID: String?
        let articleIsRead: Bool
        let articleIsSaved: Bool
        let canGoBack: Bool
        let canGoForward: Bool
        let navigationLocked: Bool
        let readerStylePresentationRequestID: UUID?
        let readerPageViewsPresentationRequestID: UUID?
        let sidebarVisible: Bool
        let directoryVisible: Bool
        let inspectorVisible: Bool
    }

    enum HistorySegment: Int {
        case back
        case forward
    }

    enum ArticleStateSegment: Int {
        case save
        case read
    }

    let toolbar: NSToolbar

    unowned let splitController: WorkspaceSplitViewController
    var environment: ReaderToolbarEnvironment
    let popoverPresenter: ReaderToolbarPopoverPresenter
    private weak var attachedWindow: NSWindow?
    private var lastSnapshot: Snapshot?
    private var lastAppliedItemIdentifiers: [NSToolbarItem.Identifier] = []
    private var preferredArticleToolbarVisibility = true
    private var isInvalidated = false

    init(
        splitController: WorkspaceSplitViewController,
        environment: ReaderToolbarEnvironment
    ) {
        self.splitController = splitController
        self.environment = environment
        toolbar = NSToolbar(identifier: .macWikiReaderScoped)
        popoverPresenter = ReaderToolbarPopoverPresenter(environment: environment)
        super.init()

        configureToolbar()
        popoverPresenter.onClose = { [weak self] in
            self?.refreshNow(forceSavedStateRefresh: true)
        }
        observeModelContext(environment.modelContext)
        refreshAndRearmObservation()
    }

    func update(environment: ReaderToolbarEnvironment) {
        guard !isInvalidated else { return }

        let contextChanged = self.environment.modelContext != environment.modelContext
        let appStateChanged = self.environment.appState !== environment.appState
        self.environment = environment
        popoverPresenter.update(environment: environment)

        if contextChanged {
            NotificationCenter.default.removeObserver(
                self,
                name: ModelContext.didSave,
                object: nil
            )
            observeModelContext(environment.modelContext)
        }
        if contextChanged || appStateChanged {
            refreshAndRearmObservation(forceSavedStateRefresh: true)
        } else {
            refreshNow()
        }
    }

    func installIfPossible() {
        guard !isInvalidated,
              let window = splitController.view.window else {
            return
        }

        if attachedWindow !== window {
            if let previousWindow = attachedWindow,
               previousWindow.toolbar === toolbar {
                previousWindow.toolbar = nil
            }
            attachedWindow = window
        }

        toolbar.displayMode = .iconOnly
        toolbar.allowsDisplayModeCustomization = false
        window.toolbarStyle = .unifiedCompact
        window.titleVisibility = .hidden

        repairStructureIfNeeded()
        refreshNow()
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        NotificationCenter.default.removeObserver(self)
        popoverPresenter.close()
        if let attachedWindow,
           attachedWindow.toolbar === toolbar {
            attachedWindow.toolbar = nil
        }
        toolbar.delegate = nil
    }

    func toolbarDefaultItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        ReaderToolbarLayout.defaultIdentifiers
    }

    func toolbarAllowedItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> [NSToolbarItem.Identifier] {
        ReaderToolbarLayout.allowedIdentifiers
    }

    func toolbarImmovableItemIdentifiers(
        _ toolbar: NSToolbar
    ) -> Set<NSToolbarItem.Identifier> {
        ReaderToolbarLayout.fixedIdentifiers
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemIdentifier: NSToolbarItem.Identifier,
        canBeInsertedAt index: Int
    ) -> Bool {
        ReaderToolbarLayout.canInsert(
            itemIdentifier,
            at: index,
            currentIdentifiers: toolbar.items.map(\.itemIdentifier)
        )
    }

    @objc private func modelContextDidSave(_ notification: Notification) {
        if let savedContext = notification.object as? ModelContext,
           savedContext != environment.modelContext {
            return
        }
        refreshNow(forceSavedStateRefresh: true)
    }

    private func configureToolbar() {
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.allowsDisplayModeCustomization = false
        toolbar.displayMode = .iconOnly
    }

    private func observeModelContext(_ modelContext: ModelContext) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelContextDidSave(_:)),
            name: ModelContext.didSave,
            object: modelContext
        )
    }

    private func refreshAndRearmObservation(forceSavedStateRefresh: Bool = false) {
        guard !isInvalidated else { return }
        let snapshot = withObservationTracking {
            makeSnapshot(forceSavedStateRefresh: forceSavedStateRefresh)
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshAndRearmObservation()
            }
        }
        apply(snapshot)
    }

    private func refreshNow(forceSavedStateRefresh: Bool = false) {
        guard !isInvalidated else { return }
        apply(makeSnapshot(forceSavedStateRefresh: forceSavedStateRefresh))
    }

    private func makeSnapshot(forceSavedStateRefresh: Bool = false) -> Snapshot {
        let appState = environment.appState
        let readerProjection = appState.activeReaderProjection
        let article = readerProjection.article
        let articleID = article?.id
        let isSaved: Bool
        if !forceSavedStateRefresh,
           lastSnapshot?.articleID == articleID,
           let lastSnapshot {
            isSaved = lastSnapshot.articleIsSaved
        } else {
            let lists = (try? environment.modelContext.fetch(FetchDescriptor<ReadingList>())) ?? []
            isSaved = article.map { currentArticle in
                lists.contains {
                    ArticleLibraryActions.containsArticle(
                        withTitle: currentArticle.title,
                        in: $0
                    )
                }
            } ?? false
        }

        return Snapshot(
            articleID: articleID,
            articleIsRead: article?.isRead == true,
            articleIsSaved: isSaved,
            canGoBack: !appState.isWikiHopNavigationLocked && readerProjection.canGoBack,
            canGoForward: !appState.isWikiHopNavigationLocked && readerProjection.canGoForward,
            navigationLocked: appState.isWikiHopNavigationLocked,
            readerStylePresentationRequestID: appState.readerStylePresentationRequestID,
            readerPageViewsPresentationRequestID: appState.readerPageViewsPresentationRequestID,
            sidebarVisible: appState.listsSidebarVisible,
            directoryVisible: appState.directoryColumnVisible,
            inspectorVisible: appState.inspectorVisible
        )
    }

    private func apply(_ snapshot: Snapshot) {
        synchronizeToolbarAttachment(hasArticle: snapshot.articleID != nil)

        let itemIdentifiers = toolbar.items.map(\.itemIdentifier)
        guard snapshot != lastSnapshot
                || itemIdentifiers != lastAppliedItemIdentifiers else {
            return
        }
        let previousSnapshot = lastSnapshot
        let articleChanged = previousSnapshot?.articleID != snapshot.articleID
        lastSnapshot = snapshot
        lastAppliedItemIdentifiers = itemIdentifiers

        updateButton(
            .macWikiSidebarToggle,
            label: snapshot.sidebarVisible ? "Hide Lists" : "Show Lists",
            symbol: "sidebar.left",
            enabled: !snapshot.navigationLocked
        )
        updateButton(
            .macWikiListContents,
            label: snapshot.directoryVisible ? "Hide List Contents" : "Show List Contents",
            symbol: "sidebar.squares.leading",
            enabled: !snapshot.navigationLocked
        )
        updateButton(
            .macWikiSearch,
            label: "Search Wikipedia",
            symbol: "magnifyingglass",
            enabled: !snapshot.navigationLocked
        )
        updateGroup(
            .macWikiHistory,
            segments: [
                ("Back", "chevron.left", snapshot.canGoBack),
                ("Forward", "chevron.right", snapshot.canGoForward)
            ]
        )

        let canActOnArticle = snapshot.articleID != nil && !snapshot.navigationLocked
        updateGroup(
            .macWikiArticleState,
            segments: [
                (
                    snapshot.articleIsSaved ? "Saved Article" : "Save Article",
                    snapshot.articleIsSaved ? "bookmark.fill" : "bookmark",
                    canActOnArticle
                ),
                (
                    snapshot.articleIsRead ? "Mark as Unread" : "Mark as Read",
                    snapshot.articleIsRead ? "checkmark.circle.fill" : "circle",
                    canActOnArticle
                )
            ]
        )
        updateButton(
            .macWikiFind,
            label: "Find in Page",
            symbol: "text.magnifyingglass",
            enabled: canActOnArticle
        )
        updateButton(
            .macWikiStyle,
            label: "Reader Style",
            symbol: "textformat.size",
            enabled: canActOnArticle
        )
        updateButton(
            .macWikiPageViews,
            label: "Page Views",
            symbol: "chart.xyaxis.line",
            enabled: canActOnArticle
        )
        updateButton(
            .macWikiOpenInBrowser,
            label: "Open in Browser",
            symbol: "safari",
            enabled: canActOnArticle
        )
        activeItem(.macWikiShare)?.isEnabled = canActOnArticle
        updateButton(
            .macWikiInspectorToggle,
            label: snapshot.inspectorVisible ? "Hide Inspector" : "Show Inspector",
            symbol: "sidebar.trailing",
            enabled: true
        )

        if articleChanged {
            popoverPresenter.closeArticlePopoverIfArticleChanged(to: snapshot.articleID)
        }
        if snapshot.readerStylePresentationRequestID
            != previousSnapshot?.readerStylePresentationRequestID,
           snapshot.readerStylePresentationRequestID != nil {
            if let item = activeItem(.macWikiStyle) {
                popoverPresenter.showReaderStyle(relativeTo: item)
            } else if let attachedWindow {
                popoverPresenter.showReaderStyle(in: attachedWindow)
            }
        }
        if snapshot.readerPageViewsPresentationRequestID
            != previousSnapshot?.readerPageViewsPresentationRequestID,
           snapshot.readerPageViewsPresentationRequestID != nil,
           let article = environment.appState.currentArticle {
            if let item = activeItem(.macWikiPageViews) {
                popoverPresenter.showPageViews(for: article, relativeTo: item)
            } else if let attachedWindow {
                popoverPresenter.showPageViews(for: article, in: attachedWindow)
            }
        }
    }

    private func repairStructureIfNeeded() {
        let identifiers = toolbar.items.map(\.itemIdentifier)
        guard !ReaderToolbarLayout.isStructurallyValid(identifiers) else { return }
        toolbar.itemIdentifiers = ReaderToolbarLayout.defaultIdentifiers
    }

    /// The customizable reader toolbar belongs to an article, not to the
    /// window's empty or Discovery state. Detaching it also prevents AppKit's
    /// standard Show Toolbar command from revealing reader controls when no
    /// article is present. A user's explicit visibility choice is restored when
    /// the next article becomes active.
    private func synchronizeToolbarAttachment(hasArticle: Bool) {
        guard let attachedWindow else { return }

        if hasArticle {
            guard attachedWindow.toolbar !== toolbar else { return }
            attachedWindow.toolbar = toolbar
            toolbar.isVisible = preferredArticleToolbarVisibility
            return
        }

        guard attachedWindow.toolbar === toolbar else { return }
        preferredArticleToolbarVisibility = toolbar.isVisible
        attachedWindow.toolbar = nil
    }

}
