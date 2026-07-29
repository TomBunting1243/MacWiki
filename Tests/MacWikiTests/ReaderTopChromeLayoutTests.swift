import AppKit
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Reader toolbar and search layout")
struct ReaderTopChromeLayoutTests {
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
            identifiers.firstIndex(of: .toggleInspector)
        )
        let inspectorBoundaryIndex = try #require(
            identifiers.firstIndex(of: .inspectorTrackingSeparator)
        )
        let inspectorModesIndex = try #require(
            identifiers.firstIndex(of: .workspaceInspectorModes)
        )

        #expect(Set(identifiers).count == identifiers.count)
        #expect(identifiers.contains(.inspectorTrackingSeparator))
        #expect(listsIndex < listsBoundaryIndex)
        #expect(listsBoundaryIndex < directoryIndex)
        #expect(directoryIndex < directoryBoundaryIndex)
        #expect(directoryBoundaryIndex < flexibleSpaceIndex)
        #expect(flexibleSpaceIndex < saveIndex)
        #expect(saveIndex < inspectorToggleIndex)
        #expect(inspectorToggleIndex + 1 == inspectorBoundaryIndex)
        #expect(inspectorBoundaryIndex + 1 == inspectorModesIndex)
        for identifier in WorkspaceToolbarLayout.readerItemIdentifiers {
            let index = try #require(identifiers.firstIndex(of: identifier))
            #expect(index > directoryBoundaryIndex)
            #expect(index < inspectorBoundaryIndex)
        }
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
}
