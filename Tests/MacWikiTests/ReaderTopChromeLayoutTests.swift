import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Reader toolbar and search layout")
struct ReaderTopChromeLayoutTests {
    @Test("main reader commands use a full-width stable native toolbar")
    func mainReaderUsesNativeWindowToolbar() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let policy = try source("Sources/MacWiki/Views/Shared/FixedWindowToolbarPolicy.swift")

        #expect(toolbar.contains("struct MainWindowReaderToolbar: ToolbarContent"))
        #expect(!toolbar.contains("CustomizableToolbarContent"))
        #expect(!toolbar.contains("ToolbarItem(id:"))
        #expect(toolbar.contains("ControlGroup(\"Workspace\")"))
        #expect(toolbar.contains("ControlGroup(\"History and Search\")"))
        #expect(toolbar.contains("ToolbarItem(placement: .navigation)"))
        #expect(toolbar.contains("ControlGroup(\"Reader Actions\")"))
        #expect(toolbar.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(toolbar.contains("ToolbarSpacer(.flexible, placement: .primaryAction)"))
        #expect(!toolbar.contains("ToolbarSpacer(.fixed)"))
        #expect(shell.contains(".toolbar {"))
        #expect(!shell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(shell.contains("TabBarView("))
        #expect(shell.contains("ReaderColumnView()"))
        #expect(shell.contains("readerAccessory: workspaceEnvironment("))
        #expect(shell.contains("inspectorAccessory: workspaceEnvironment("))
        #expect(!toolbar.contains("NSButton"))
        #expect(!toolbar.contains(".controlSize(.small)"))
        #expect(!toolbar.contains(".frame(width:"))
        #expect(policy.contains("toolbar.allowsUserCustomization = false"))
        #expect(policy.contains("toolbar.autosavesConfiguration = false"))
        #expect(policy.contains("NSToolbarItem.Identifier.inspectorTrackingSeparator"))
        #expect(policy.contains("NSToolbarItem.Identifier.toggleInspector"))
        #expect(policy.contains("if !toolbar.items.contains(where: { $0.itemIdentifier == toggle })"))
        #expect(policy.contains("if !toolbar.items.contains(where: { $0.itemIdentifier == separator })"))
        #expect(!policy.contains("toolbar.removeItem(at:"))
        #expect(policy.contains("WorkspaceInspectorResponder"))
        #expect(shell.contains("FixedWindowToolbarPolicy(relaysNestedWorkspaceInspector: true)"))
        #expect(policy.contains("if trackingItem.dividerIndex != dividerIndex"))
        #expect(!toolbar.contains("toggle-reader-inspector"))
        #expect(!toolbar.contains("appState.toggleInspectorVisibility()"))
    }

    @Test("navigation remains leading and reader actions remain trailing")
    func readerToolbarUsesStableEdgeAlignment() throws {
        for path in [
            "Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift",
            "Sources/MacWiki/Views/Shared/ArticleWindowReaderToolbar.swift"
        ] {
            let toolbar = try source(path)
            let leadingPlacement = try #require(toolbar.range(of: "ToolbarItem(placement: .navigation)"))
            let leadingControl = try #require(toolbar.range(of: "ControlGroup("))
            let flexibleSpacer = try #require(toolbar.range(of: "ToolbarSpacer(.flexible, placement: .primaryAction)"))
            let trailingPlacement = try #require(toolbar.range(of: "ToolbarItem(placement: .primaryAction)"))
            let trailingControl = try #require(toolbar.range(of: "ControlGroup(\"Reader Actions\")"))
            let saveAction = try #require(toolbar.range(of: "Button(\"Save Article\""))
            let shareAction = try #require(toolbar.range(of: "ShareLink(item: article.url)"))

            #expect(leadingPlacement.lowerBound < leadingControl.lowerBound)
            #expect(leadingControl.lowerBound < flexibleSpacer.lowerBound)
            #expect(flexibleSpacer.lowerBound < trailingPlacement.lowerBound)
            #expect(trailingPlacement.lowerBound < trailingControl.lowerBound)
            #expect(trailingPlacement.lowerBound < saveAction.lowerBound)
            #expect(saveAction.lowerBound < shareAction.lowerBound)
        }
    }

    @Test("every main reader command remains natively reachable")
    func mainReaderToolbarPreservesEveryCommandPath() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")

        for action in [
            "Hide Lists", "Show Lists", "Hide List Contents", "Show List Contents", "Back", "Forward",
            "Search Wikipedia", "Save Article", "Mark as Read", "Find in Page",
            "Reader Style", "Page Views", "Open in Browser", "Share"
        ] {
            #expect(toolbar.contains(action))
        }
        #expect(toolbar.contains("appState.toggleListsSidebarVisibility()"))
        #expect(toolbar.contains("systemImage: \"sidebar.left\""))
        #expect(toolbar.contains("reader-find-in-page"))
        #expect(toolbar.contains("SaveToListPopover(article: article)"))
        #expect(toolbar.contains("ReaderStylePopover()"))
        #expect(toolbar.contains("SidebarPageViewsPopoverContent("))
        #expect(toolbar.contains("ReadStateSync.applyReadState("))
        #expect(toolbar.contains("ShareLink(item: article.url)"))
        let policy = try source("Sources/MacWiki/Views/Shared/FixedWindowToolbarPolicy.swift")
        #expect(policy.contains("NSToolbarItem.Identifier.toggleInspector"))
        #expect(policy.contains("NSToolbarItem.Identifier.inspectorTrackingSeparator"))
        #expect(!policy.contains("toolbar.removeItem(at:"))
    }

    @Test("menu presentation requests reach native toolbar popovers")
    func menuRequestsReachToolbarPopovers() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let mainToolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")
        let articleToolbar = try source("Sources/MacWiki/Views/Shared/ArticleWindowReaderToolbar.swift")

        #expect(shell.contains(".onChange(of: appState.readerStylePresentationRequestID)"))
        #expect(shell.contains("showsReaderStylePopover = true"))
        #expect(shell.contains(".onChange(of: appState.readerPageViewsPresentationRequestID)"))
        #expect(shell.contains("showsPageViewsPopover = true"))
        for toolbar in [mainToolbar, articleToolbar] {
            #expect(toolbar.components(separatedBy: "dismissOtherPopovers(keeping:").count - 1 == 3)
        }
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
