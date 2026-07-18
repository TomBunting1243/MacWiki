import AppKit
import os

private let workspaceToolbarLogger = Logger(subsystem: "com.macwiki", category: "workspace-toolbar")

/// Sole owner of the main window's toolbar. Every command is a real AppKit
/// toolbar item, so native sizing, hover treatment, accessibility, validation,
/// and compact-width overflow remain available without hand-built chrome.
@MainActor
final class WorkspaceToolbarController: NSObject, NSToolbarDelegate,
    NSToolbarItemValidation, NSSharingServicePickerToolbarItemDelegate
{
    private weak var splitController: AppKitWorkspaceNavigationController?
    private var configuration: WorkspaceToolbarConfiguration
    private weak var installedWindow: NSWindow?
    private var installedToolbar: NSToolbar?
    private var previousToolbarStyle: NSWindow.ToolbarStyle?
    private var previousTitleVisibility: NSWindow.TitleVisibility?
    private let popoverPresenter = WorkspaceToolbarPopoverPresenter()
    private var lastConsumedReaderStyleRequestID: UUID?
    private var lastConsumedPageViewsRequestID: UUID?
    private let inspectorModesController: WorkspaceInspectorToolbarItemController

    init(
        splitController: AppKitWorkspaceNavigationController,
        configuration: WorkspaceToolbarConfiguration
    ) {
        self.splitController = splitController
        self.configuration = configuration
        inspectorModesController = WorkspaceInspectorToolbarItemController(
            appState: configuration.appState,
            isPlaneVisible: splitController.inspectorPaneVisible
        )
        super.init()
    }

    func install(on window: NSWindow) {
        guard let splitController,
              splitController.view.window === window else {
            return
        }

        if installedWindow === window,
           let installedToolbar,
           window.toolbar === installedToolbar {
            return
        }

        if installedToolbar != nil {
            invalidate()
        }

        // ADR-012: never replace or adopt a toolbar owned by SwiftUI or
        // another controller. The main scene intentionally creates none.
        guard window.toolbar == nil else {
            workspaceToolbarLogger.fault(
                "Refusing to replace a non-owned main-window toolbar"
            )
            return
        }

        let toolbar = NSToolbar(identifier: WorkspaceToolbarLayout.toolbarIdentifier)
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        toolbar.autosavesConfiguration = false

        previousToolbarStyle = window.toolbarStyle
        previousTitleVisibility = window.titleVisibility
        installedWindow = window
        installedToolbar = toolbar

        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.toolbar = toolbar

        refreshItems()
        consumePresentationRequests()
    }

    func update(configuration: WorkspaceToolbarConfiguration) {
        let previousSnapshot = self.configuration.snapshot
        self.configuration = configuration
        inspectorModesController.update(appState: configuration.appState)

        if previousSnapshot.articleID != configuration.snapshot.articleID {
            popoverPresenter.close()
        }

        guard previousSnapshot != configuration.snapshot else {
            inspectorModesController.updateSelection(to: configuration.inspectorMode)
            return
        }
        refreshItems()
        consumePresentationRequests()
    }

    func setInspectorPlaneVisible(_ isVisible: Bool) {
        inspectorModesController.setPlaneVisible(isVisible, in: installedToolbar)
    }

    func invalidate() {
        popoverPresenter.close()

        let window = installedWindow
        let toolbar = installedToolbar
        let priorStyle = previousToolbarStyle
        let priorTitleVisibility = previousTitleVisibility
        let stillOwnsToolbar = window?.toolbar === toolbar
        let stillOwnsWindowChrome = stillOwnsToolbar || window?.toolbar == nil

        if let shareItem = toolbar?.items.first(where: {
            $0.itemIdentifier == .workspaceShare
        }) as? NSSharingServicePickerToolbarItem {
            shareItem.delegate = nil
        }
        toolbar?.delegate = nil

        installedToolbar = nil
        installedWindow = nil
        previousToolbarStyle = nil
        previousTitleVisibility = nil

        guard let window else { return }
        if stillOwnsToolbar {
            window.toolbar = nil
        }
        if stillOwnsWindowChrome {
            if let priorStyle {
                window.toolbarStyle = priorStyle
            }
            if let priorTitleVisibility {
                window.titleVisibility = priorTitleVisibility
            }
        }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        WorkspaceToolbarLayout.defaultItemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        WorkspaceToolbarLayout.defaultItemIdentifiers
    }

    func toolbarImmovableItemIdentifiers(_ toolbar: NSToolbar) -> Set<NSToolbarItem.Identifier> {
        Set(WorkspaceToolbarLayout.defaultItemIdentifiers)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard let splitController else { return nil }

        switch itemIdentifier {
        case .workspaceListsDirectoryBoundary:
            return WorkspaceToolbarItemFactory.trackingSeparator(
                identifier: itemIdentifier,
                splitView: splitController.splitView,
                dividerIndex: 0
            )
        case .workspaceDirectoryReaderBoundary:
            return WorkspaceToolbarItemFactory.trackingSeparator(
                identifier: itemIdentifier,
                splitView: splitController.splitView,
                dividerIndex: 1
            )
        case .workspaceReaderInspectorBoundary:
            return WorkspaceToolbarItemFactory.trackingSeparator(
                identifier: itemIdentifier,
                splitView: splitController.splitView,
                dividerIndex: 2
            )
        case .workspaceInspectorModes:
            return inspectorModesController.makeItem(identifier: itemIdentifier)
        case .workspaceLists:
            let item = WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Lists",
                symbol: "sidebar.left",
                target: self,
                action: #selector(toggleLists(_:))
            )
            item.visibilityPriority = .high
            return item
        case .workspaceDirectory:
            let item = WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "List Contents",
                symbol: "sidebar.squares.leading",
                target: self,
                action: #selector(toggleDirectory(_:))
            )
            item.visibilityPriority = .high
            return item
        case .workspaceBack:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Back",
                symbol: "chevron.left",
                target: self,
                action: #selector(goBack(_:))
            )
        case .workspaceForward:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Forward",
                symbol: "chevron.right",
                target: self,
                action: #selector(goForward(_:))
            )
        case .workspaceSearch:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Search Wikipedia",
                symbol: "magnifyingglass",
                target: self,
                action: #selector(searchWikipedia(_:))
            )
        case .workspaceSave:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Save Article",
                symbol: "bookmark",
                target: self,
                action: #selector(showSavePopover(_:))
            )
        case .workspaceReadState:
            let item = WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Mark as Read",
                symbol: "circle",
                target: self,
                action: #selector(toggleReadState(_:))
            )
            item.possibleLabels = ["Mark as Read", "Mark as Unread"]
            return item
        case .workspaceFind:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Find in Page",
                symbol: "text.magnifyingglass",
                target: self,
                action: #selector(findInPage(_:))
            )
        case .workspaceReaderStyle:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Reader Style",
                symbol: "textformat.size",
                target: self,
                action: #selector(showReaderStylePopover(_:))
            )
        case .workspacePageViews:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Page Views",
                symbol: "chart.xyaxis.line",
                target: self,
                action: #selector(showPageViewsPopover(_:))
            )
        case .workspaceOpenBrowser:
            return WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Open in Browser",
                symbol: "safari",
                target: self,
                action: #selector(openInBrowser(_:))
            )
        case .workspaceShare:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Share"
            item.paletteLabel = "Share"
            item.toolTip = "Share Article"
            item.image = NSImage(
                systemSymbolName: "square.and.arrow.up",
                accessibilityDescription: "Share Article"
            )
            item.isBordered = true
            item.style = .plain
            item.delegate = self
            return item
        case .workspaceInspectorToggle:
            let item = WorkspaceToolbarItemFactory.button(
                identifier: itemIdentifier,
                label: "Inspector",
                symbol: "sidebar.right",
                target: self,
                action: #selector(toggleInspector(_:))
            )
            item.visibilityPriority = .high
            return item
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        let snapshot = configuration.snapshot
        let hasArticle = snapshot.articleID != nil

        switch item.itemIdentifier {
        case .workspaceLists, .workspaceDirectory, .workspaceSearch:
            return !snapshot.navigationLocked
        case .workspaceBack:
            return hasArticle && snapshot.canGoBack && !snapshot.navigationLocked
        case .workspaceForward:
            return hasArticle && snapshot.canGoForward && !snapshot.navigationLocked
        case .workspaceSave, .workspaceReadState, .workspaceFind,
                .workspaceReaderStyle, .workspacePageViews,
                .workspaceOpenBrowser, .workspaceShare:
            return hasArticle && !snapshot.navigationLocked
        case .workspaceInspectorToggle:
            return true
        case .workspaceInspectorModes:
            return inspectorModesController.isPlaneVisible
        default:
            return true
        }
    }

    func items(
        for pickerToolbarItem: NSSharingServicePickerToolbarItem
    ) -> [Any] {
        guard let url = configuration.snapshot.articleURL else { return [] }
        return [url]
    }

    @objc private func toggleLists(_ sender: Any?) {
        configuration.appState.toggleListsSidebarVisibility()
        refreshFromLiveState()
    }

    @objc private func toggleDirectory(_ sender: Any?) {
        configuration.appState.toggleDirectoryColumnVisibility()
        refreshFromLiveState()
    }

    @objc private func goBack(_ sender: Any?) {
        configuration.appState.goBack()
        refreshFromLiveState()
    }

    @objc private func goForward(_ sender: Any?) {
        configuration.appState.goForward()
        refreshFromLiveState()
    }

    @objc private func searchWikipedia(_ sender: Any?) {
        configuration.appState.startSearch(context: .navigation)
    }

    @objc private func showSavePopover(_ sender: NSToolbarItem) {
        presentPopover(.save, relativeTo: sender)
    }

    @objc private func toggleReadState(_ sender: Any?) {
        let appState = configuration.appState
        guard let article = appState.currentArticle else { return }
        _ = ReadStateSync.applyReadState(
            !article.isRead,
            for: article,
            in: configuration.modelContext,
            appState: appState
        )
        refreshFromLiveState()
    }

    @objc private func findInPage(_ sender: Any?) {
        configuration.appState.presentFindOnPage()
    }

    @objc private func showReaderStylePopover(_ sender: NSToolbarItem) {
        presentPopover(.readerStyle, relativeTo: sender)
    }

    @objc private func showPageViewsPopover(_ sender: NSToolbarItem) {
        presentPopover(.pageViews, relativeTo: sender)
    }

    @objc private func openInBrowser(_ sender: Any?) {
        guard let url = configuration.snapshot.articleURL else { return }
        configuration.openURL(url)
    }

    @objc private func toggleInspector(_ sender: Any?) {
        splitController?.toggleInspector(sender)
    }

    private func refreshFromLiveState() {
        update(
            configuration: WorkspaceToolbarConfiguration(
                appState: configuration.appState,
                modelContext: configuration.modelContext,
                openURL: configuration.openURL
            )
        )
    }

    private func refreshItems() {
        guard let toolbar = installedToolbar else { return }
        let snapshot = configuration.snapshot

        inspectorModesController.setPlaneVisible(
            inspectorModesController.isPlaneVisible,
            in: toolbar
        )
        toolbar.validateVisibleItems()

        for item in toolbar.items {
            // The sharing picker has no target/action pair, so AppKit's target
            // validation does not apply our delegate validator to it. Resolve
            // every item from the same snapshot after native validation.
            item.isEnabled = validateToolbarItem(item)
            switch item.itemIdentifier {
            case .workspaceLists:
                item.toolTip = snapshot.listsVisible ? "Hide Lists" : "Show Lists"
            case .workspaceDirectory:
                item.toolTip = snapshot.directoryVisible
                    ? "Hide List Contents"
                    : "Show List Contents"
            case .workspaceReadState:
                let label = snapshot.articleIsRead ? "Mark as Unread" : "Mark as Read"
                item.label = label
                item.toolTip = label
                item.image = NSImage(
                    systemSymbolName: snapshot.articleIsRead ? "checkmark.circle.fill" : "circle",
                    accessibilityDescription: label
                )
            case .workspaceInspectorToggle:
                item.toolTip = snapshot.inspectorVisible
                    ? "Hide Inspector"
                    : "Show Inspector"
            case .workspaceInspectorModes:
                inspectorModesController.updateSelection(
                    of: item,
                    to: configuration.inspectorMode
                )
            default:
                break
            }
        }
    }

    private func consumePresentationRequests() {
        guard installedToolbar != nil,
              configuration.snapshot.articleID != nil else {
            return
        }

        if let requestID = configuration.snapshot.readerStyleRequestID,
           requestID != lastConsumedReaderStyleRequestID {
            lastConsumedReaderStyleRequestID = requestID
            presentPopover(.readerStyle, relativeTo: .workspaceReaderStyle)
        }

        if let requestID = configuration.snapshot.pageViewsRequestID,
           requestID != lastConsumedPageViewsRequestID {
            lastConsumedPageViewsRequestID = requestID
            presentPopover(.pageViews, relativeTo: .workspacePageViews)
        }
    }

    private func presentPopover(
        _ kind: WorkspaceToolbarPopoverPresenter.Kind,
        relativeTo identifier: NSToolbarItem.Identifier
    ) {
        guard let toolbar = installedToolbar,
              installedWindow?.toolbar === toolbar,
              let item = toolbar.items.first(where: {
            $0.itemIdentifier == identifier
        }), item.toolbar === toolbar else {
            popoverPresenter.close()
            return
        }
        presentPopover(kind, relativeTo: item)
    }

    private func presentPopover(
        _ kind: WorkspaceToolbarPopoverPresenter.Kind,
        relativeTo item: NSToolbarItem
    ) {
        guard let toolbar = installedToolbar,
              installedWindow?.toolbar === toolbar,
              item.toolbar === toolbar,
              toolbar.items.contains(where: { $0 === item }) else {
            popoverPresenter.close()
            return
        }
        popoverPresenter.present(
            kind,
            relativeTo: item,
            configuration: configuration
        )
    }
}
