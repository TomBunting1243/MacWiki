import AppKit
import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Reader toolbar and search layout")
struct ReaderTopChromeLayoutTests {
    @Test("main reader commands use a full-width customizable native toolbar")
    func mainReaderUsesNativeWindowToolbar() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(toolbar.contains("struct MainWindowReaderToolbar: CustomizableToolbarContent"))
        #expect(toolbar.contains("main-window-native-toolbar-v1"))
        #expect(toolbar.contains("ControlGroup(\"Navigation\")"))
        #expect(shell.contains(".toolbar(id: MainWindowReaderToolbarIdentifier.configuration)"))
        #expect(shell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(shell.contains("TabBarView("))
        #expect(shell.contains("ReaderColumnView()"))
        #expect(!toolbar.contains("NSButton"))
        #expect(!toolbar.contains(".controlSize(.small)"))
        #expect(!toolbar.contains(".frame(width:"))
    }

    @Test("every main reader command remains natively reachable")
    func mainReaderToolbarPreservesEveryCommandPath() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")

        for action in [
            "Hide List Contents", "Show List Contents", "Back", "Forward",
            "Search Wikipedia", "Save Article", "Mark as Read", "Find in Page",
            "Reader Style", "Page Views", "Open in Browser", "Share",
            "Hide Inspector", "Show Inspector"
        ] {
            #expect(toolbar.contains(action))
        }
        #expect(toolbar.contains("reader-find-in-page"))
        #expect(toolbar.contains("SaveToListPopover(article: article)"))
        #expect(toolbar.contains("ReaderStylePopover()"))
        #expect(toolbar.contains("SidebarPageViewsPopoverContent("))
        #expect(toolbar.contains("ReadStateSync.applyReadState("))
        #expect(toolbar.contains("ShareLink(item: article.url)"))
    }

    @Test("menu presentation requests reach native toolbar popovers")
    func menuRequestsReachToolbarPopovers() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(shell.contains(".onChange(of: appState.readerStylePresentationRequestID)"))
        #expect(shell.contains("showsReaderStylePopover = true"))
        #expect(shell.contains(".onChange(of: appState.readerPageViewsPresentationRequestID)"))
        #expect(shell.contains("showsPageViewsPopover = true"))
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
