import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Reader toolbar and search layout")
struct ReaderTopChromeLayoutTests {
    @Test("main reader commands use one directly owned native AppKit toolbar")
    func mainReaderUsesNativeWindowToolbar() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let configuration = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarConfiguration.swift")
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let tabAccessories = try source("Sources/MacWiki/Views/Components/ReaderTabAccessoryCluster.swift")

        #expect(toolbar.contains("final class WorkspaceToolbarController: NSObject,"))
        #expect(toolbar.contains("NSToolbarDelegate"))
        #expect(toolbar.contains("NSToolbarItemValidation"))
        #expect(toolbar.contains("NSSharingServicePickerToolbarItemDelegate"))
        #expect(toolbar.contains("let toolbar = NSToolbar(identifier: WorkspaceToolbarLayout.toolbarIdentifier)"))
        #expect(toolbar.contains("guard window.toolbar == nil else"))
        #expect(toolbar.contains("window.toolbar = toolbar"))
        #expect(toolbar.contains("toolbar.allowsUserCustomization = false"))
        #expect(toolbar.contains("toolbar.autosavesConfiguration = false"))
        #expect(toolbar.contains("NSToolbarItem(itemIdentifier: identifier)"))
        #expect(toolbar.contains("NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)"))
        #expect(toolbar.contains("item.target = self"))
        #expect(toolbar.contains("item.action = action"))
        #expect(!toolbar.contains("NSHostingView"))
        #expect(configuration.contains("struct WorkspaceToolbarSnapshot: Equatable"))
        #expect(configuration.contains("mode and Reader/WebKit projection state are deliberately absent"))
        #expect(bridge.contains("toolbarController = WorkspaceToolbarController("))
        #expect(bridge.contains("toolbarController?.update(configuration: configuration)"))
        #expect(shell.contains("toolbarConfiguration: WorkspaceToolbarConfiguration("))
        #expect(!shell.contains(".toolbar {"))
        #expect(!shell.contains("FixedWindowToolbarPolicy()"))
        #expect(shell.contains("TabBarView("))
        #expect(shell.contains("ReaderColumnView()"))
        #expect(shell.contains("readerAccessory: workspaceEnvironment("))
        #expect(shell.contains("InspectorColumnView(includesHeader: false)"))
        #expect(shell.contains("inspectorAccessory: workspaceEnvironment("))
        #expect(shell.contains("InspectorHeaderBar(selection: $appState.inspectorMode)"))
        #expect(!tabAccessories.contains("appState.toggleInspectorVisibility()"))
        #expect(!tabAccessories.contains("toggle-reader-inspector"))
        #expect(toolbar.contains("configuration.appState.toggleInspectorVisibility()"))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot
                .appending(path: "Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")
                .path
        ))
    }

    @Test("native boundaries keep every Reader item before the Inspector plane")
    func readerToolbarUsesStableEdgeAlignment() throws {
        let identifiers = WorkspaceToolbarLayout.defaultItemIdentifiers
        let listsIndex = try #require(identifiers.firstIndex(of: .workspaceLists))
        let listsBoundaryIndex = try #require(
            identifiers.firstIndex(of: .workspaceListsDirectoryBoundary)
        )
        let directoryIndex = try #require(identifiers.firstIndex(of: .workspaceDirectory))
        let directoryBoundaryIndex = try #require(
            identifiers.firstIndex(of: .workspaceDirectoryReaderBoundary)
        )
        let flexibleSpaceIndex = try #require(identifiers.firstIndex(of: .flexibleSpace))
        let saveIndex = try #require(identifiers.firstIndex(of: .workspaceSave))
        let inspectorToggleIndex = try #require(
            identifiers.firstIndex(of: .workspaceInspectorToggle)
        )
        let inspectorBoundaryIndex = try #require(
            identifiers.firstIndex(of: .workspaceReaderInspectorBoundary)
        )

        #expect(Set(identifiers).count == identifiers.count)
        #expect(listsIndex < listsBoundaryIndex)
        #expect(listsBoundaryIndex < directoryIndex)
        #expect(directoryIndex < directoryBoundaryIndex)
        #expect(directoryBoundaryIndex < flexibleSpaceIndex)
        #expect(flexibleSpaceIndex < saveIndex)
        #expect(saveIndex < inspectorToggleIndex)
        #expect(inspectorToggleIndex + 1 == inspectorBoundaryIndex)
        for identifier in WorkspaceToolbarLayout.readerItemIdentifiers {
            let index = try #require(identifiers.firstIndex(of: identifier))
            #expect(index > directoryBoundaryIndex)
            #expect(index < inspectorBoundaryIndex)
        }

        let toolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        #expect(toolbar.components(separatedBy: "NSTrackingSeparatorToolbarItem(").count - 1 == 1)
        #expect(toolbar.contains("dividerIndex: 0"))
        #expect(toolbar.contains("dividerIndex: 1"))
        #expect(toolbar.contains("dividerIndex: 2"))
        #expect(toolbar.contains("item.visibilityPriority = .high"))

        // Standalone article windows intentionally retain SwiftUI toolbar placement.
        let articleToolbar = try source("Sources/MacWiki/Views/Shared/ArticleWindowReaderToolbar.swift")
        let leadingPlacement = try #require(articleToolbar.range(of: "ToolbarItem(placement: .navigation)"))
        let flexibleSpacer = try #require(
            articleToolbar.range(of: "ToolbarSpacer(.flexible, placement: .primaryAction)")
        )
        let trailingPlacement = try #require(
            articleToolbar.range(of: "ToolbarItem(placement: .primaryAction)")
        )
        let saveAction = try #require(articleToolbar.range(of: "Button(\"Save Article\""))
        let shareAction = try #require(articleToolbar.range(of: "ShareLink(item: article.url)"))
        #expect(leadingPlacement.lowerBound < flexibleSpacer.lowerBound)
        #expect(flexibleSpacer.lowerBound < trailingPlacement.lowerBound)
        #expect(trailingPlacement.lowerBound < saveAction.lowerBound)
        #expect(saveAction.lowerBound < shareAction.lowerBound)
    }

    @Test("every main reader command remains natively reachable")
    func mainReaderToolbarPreservesEveryCommandPath() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let popoverPresenter = try source(
            "Sources/MacWiki/Views/Shared/WorkspaceToolbarPopoverPresenter.swift"
        )
        let tabAccessories = try source("Sources/MacWiki/Views/Components/ReaderTabAccessoryCluster.swift")

        for action in [
            "Lists", "List Contents", "Back", "Forward",
            "Search Wikipedia", "Save Article", "Mark as Read", "Find in Page",
            "Reader Style", "Page Views", "Open in Browser", "Share"
        ] {
            #expect(toolbar.contains(action))
        }
        #expect(toolbar.contains("configuration.appState.toggleListsSidebarVisibility()"))
        #expect(toolbar.contains("configuration.appState.toggleDirectoryColumnVisibility()"))
        #expect(toolbar.contains("configuration.appState.goBack()"))
        #expect(toolbar.contains("configuration.appState.goForward()"))
        #expect(toolbar.contains("configuration.appState.startSearch(context: .navigation)"))
        #expect(toolbar.contains("configuration.appState.presentFindOnPage()"))
        #expect(toolbar.contains("configuration.appState.toggleInspectorVisibility()"))
        #expect(popoverPresenter.contains("SaveToListPopover(article: article)"))
        #expect(popoverPresenter.contains("ReaderStylePopover()"))
        #expect(popoverPresenter.contains("SidebarPageViewsPopoverContent("))
        #expect(toolbar.contains("ReadStateSync.applyReadState("))
        #expect(toolbar.contains("NSSharingServicePickerToolbarItem"))
        #expect(toolbar.contains("configuration.openURL(url)"))
        #expect(toolbar.contains("func validateToolbarItem(_ item: NSToolbarItem) -> Bool"))
        #expect(toolbar.contains("toolbar.validateVisibleItems()"))
        #expect(toolbar.contains("? \"Hide Inspector\""))
        #expect(toolbar.contains(": \"Show Inspector\""))
        #expect(!tabAccessories.contains("Hide Inspector"))
        #expect(!tabAccessories.contains("Show Inspector"))
    }

    @Test("menu presentation requests reach native toolbar popovers")
    func menuRequestsReachToolbarPopovers() throws {
        let configuration = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarConfiguration.swift")
        let mainToolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let popoverPresenter = try source(
            "Sources/MacWiki/Views/Shared/WorkspaceToolbarPopoverPresenter.swift"
        )
        let articleToolbar = try source("Sources/MacWiki/Views/Shared/ArticleWindowReaderToolbar.swift")

        #expect(configuration.contains("readerStyleRequestID: appState.readerStylePresentationRequestID"))
        #expect(configuration.contains("pageViewsRequestID: appState.readerPageViewsPresentationRequestID"))
        #expect(popoverPresenter.contains("private var activePopover: NSPopover?"))
        #expect(popoverPresenter.contains("NSPopoverDelegate"))
        #expect(popoverPresenter.contains("func popoverDidClose(_ notification: Notification)"))
        #expect(mainToolbar.contains("private func consumePresentationRequests()"))
        #expect(mainToolbar.contains("presentPopover(.readerStyle, relativeTo: .workspaceReaderStyle)"))
        #expect(mainToolbar.contains("presentPopover(.pageViews, relativeTo: .workspacePageViews)"))
        #expect(mainToolbar.contains("popoverPresenter.close()"))
        #expect(popoverPresenter.contains("popover.behavior = .transient"))
        #expect(popoverPresenter.contains("popover.show(relativeTo: item)"))
        #expect(articleToolbar.components(separatedBy: "dismissOtherPopovers(keeping:").count - 1 == 3)
    }

    @Test("List Contents search is an embedded native AppKit search field")
    func listContentsOwnsNativeSearchField() throws {
        let nativeField = try source("Sources/MacWiki/Views/Sidebar/Search/NativeSidebarSearchField.swift")
        let header = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchHeaderView.swift")
        let searchSurface = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")

        #expect(nativeField.contains("NSSearchField()"))
        #expect(nativeField.contains("sendsSearchStringImmediately = true"))
        #expect(nativeField.contains("sidebar-search-field"))
        #expect(nativeField.contains("moveDown"))
        #expect(nativeField.contains("insertNewline"))
        #expect(nativeField.contains("cancelOperation"))
        #expect(header.contains("NativeSidebarSearchField("))
        #expect(!searchSurface.contains(".padding(.top, ReaderTabLaneMetrics.height)"))
    }

    @Test("native search field publishes text and routes editing commands")
    @MainActor
    func nativeSearchFieldRoutesEditingCommands() {
        var text = ""
        var focused = true
        var moveDownCount = 0
        var moveUpCount = 0
        var submitCount = 0
        var cancelCount = 0
        let field = NativeSidebarSearchField(
            text: Binding(get: { text }, set: { text = $0 }),
            isFocused: Binding(get: { focused }, set: { focused = $0 }),
            onMoveDown: { moveDownCount += 1 },
            onMoveUp: { moveUpCount += 1 },
            onSubmit: { submitCount += 1 },
            onCancel: { cancelCount += 1 }
        )
        let coordinator = NativeSidebarSearchField.Coordinator(parent: field)
        let searchField = NSSearchField()
        let editor = NSTextView()

        searchField.stringValue = "SwiftUI"
        coordinator.searchFieldChanged(searchField)
        #expect(text == "SwiftUI")

        #expect(coordinator.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.moveDown(_:))))
        #expect(coordinator.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.moveUp(_:))))
        #expect(coordinator.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(moveDownCount == 1)
        #expect(moveUpCount == 1)
        #expect(submitCount == 1)

        #expect(coordinator.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(text.isEmpty)
        #expect(cancelCount == 0)

        #expect(coordinator.control(searchField, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!focused)
        #expect(cancelCount == 1)
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
