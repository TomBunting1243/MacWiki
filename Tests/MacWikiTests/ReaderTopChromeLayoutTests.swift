import Foundation
import AppKit
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Reader top chrome layout")
struct ReaderTopChromeLayoutTests {
    @Test("main reader chrome is owned by a native split-item accessory")
    func readerChromeUsesNativeSplitItemAccessory() throws {
        let workspace = try source("Sources/MacWiki/Views/Shared/WorkspaceSplitViewController.swift")
        let bridge = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(workspace.contains("readerItem.topAlignedAccessoryViewControllers"))
        #expect(workspace.contains("setReaderTopAccessoryVisible"))
        #expect(bridge.contains("NSSplitViewItemAccessoryViewController"))
        #expect(bridge.contains("preferredScrollEdgeEffectStyle = .soft"))
        #expect(bridge.contains("hostingController.sizingOptions = [.intrinsicContentSize, .preferredContentSize]"))
        #expect(bridge.contains("lastRequestedReaderChromeVisible"))
        #expect(shell.contains("readerChromeVisible: !appState.isWikiHopNavigationLocked"))
        #expect(shell.contains("readerRevision: readerPresentationRevision"))
        #expect(shell.contains("appState.showFindOnPage ? \"find-visible\" : \"find-hidden\""))
        #expect(shell.contains("appState.findOnPageFocusRequestID?.uuidString"))
        #expect(!workspace.contains("window.toolbar"))
        #expect(!shell.contains("ReaderToolbarEnvironment("))
    }

    @Test("reader actions adapt by intrinsic fit and preserve every command path")
    func readerActionsUseIntrinsicNativeLayouts() throws {
        let chrome = try source("Sources/MacWiki/Views/Shared/ReaderTopChromeView.swift")

        #expect(chrome.contains("ViewThatFits(in: .horizontal)"))
        #expect(chrome.contains("ControlGroup"))
        #expect(!chrome.contains("GeometryReader"))
        #expect(!chrome.contains("NSToolbar"))
        #expect(chrome.contains("toggleListsSidebarVisibility"))
        #expect(chrome.contains("toggleDirectoryColumnVisibility"))
        #expect(chrome.contains("toggleInspectorVisibility"))
        #expect(chrome.contains("readerStylePresentationRequestID"))
        #expect(chrome.contains("readerPageViewsPresentationRequestID"))
        #expect(chrome.contains(".popover(isPresented: $showingSavePopover)"))
        #expect(chrome.contains("presentSavePopover()"))
        #expect(chrome.contains("presentReaderStylePopover()"))
        #expect(chrome.contains("presentPageViewsPopover()"))
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
        let testsURL = URL(fileURLWithPath: #filePath)
        let packageRoot = testsURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
