import AppKit
import SwiftData
import SwiftUI
import Testing

@testable import MacWiki

@Suite
@MainActor
struct ReaderToolbarLayoutTests {
    @Test func defaultLayoutContainsOneFixedBoundaryForEveryPaneDivider() {
        let identifiers = ReaderToolbarLayout.defaultIdentifiers

        #expect(ReaderToolbarLayout.isStructurallyValid(identifiers))
        #expect(
            identifiers.filter { $0 == .macWikiSidebarDirectoryBoundary }.count == 1
        )
        #expect(
            identifiers.filter { $0 == .macWikiDirectoryReaderBoundary }.count == 1
        )
        #expect(
            identifiers.filter { $0 == .macWikiReaderInspectorBoundary }.count == 1
        )
        #expect(identifiers.first == .toggleSidebar)
        #expect(identifiers.last == .toggleInspector)
    }

    @Test func onlyReaderItemsAndSpacesCanMoveInsideReaderBoundaries() {
        let identifiers = ReaderToolbarLayout.defaultIdentifiers
        let leftBoundary = identifiers.firstIndex(of: .macWikiDirectoryReaderBoundary)
        let rightBoundary = identifiers.firstIndex(of: .macWikiReaderInspectorBoundary)

        #expect(leftBoundary != nil)
        #expect(rightBoundary != nil)
        guard let leftBoundary, let rightBoundary else { return }

        for identifier in ReaderToolbarLayout.readerIdentifiers.union([.space, .flexibleSpace]) {
            #expect(
                ReaderToolbarLayout.canInsert(
                    identifier,
                    at: NSNotFound,
                    currentIdentifiers: identifiers
                )
            )
            for index in 0...identifiers.count {
                #expect(
                    ReaderToolbarLayout.canInsert(
                        identifier,
                        at: index,
                        currentIdentifiers: identifiers
                    ) == (index > leftBoundary && index <= rightBoundary)
                )
            }
        }

        for identifier in ReaderToolbarLayout.fixedIdentifiers {
            #expect(
                !ReaderToolbarLayout.canInsert(
                    identifier,
                    at: NSNotFound,
                    currentIdentifiers: identifiers
                )
            )
            #expect(
                !ReaderToolbarLayout.canInsert(
                    identifier,
                    at: leftBoundary + 1,
                    currentIdentifiers: identifiers
                )
            )
        }
    }

    @Test func structuralValidationRejectsMissingOrCrossBoundaryItems() {
        var missingBoundary = ReaderToolbarLayout.defaultIdentifiers
        missingBoundary.removeAll { $0 == .macWikiDirectoryReaderBoundary }
        #expect(!ReaderToolbarLayout.isStructurallyValid(missingBoundary))

        var readerItemInListZone = ReaderToolbarLayout.defaultIdentifiers
        readerItemInListZone.removeAll { $0 == .macWikiStyle }
        let listInsertionIndex = readerItemInListZone.firstIndex(
            of: .macWikiDirectoryReaderBoundary
        ) ?? 0
        readerItemInListZone.insert(.macWikiStyle, at: listInsertionIndex)
        #expect(!ReaderToolbarLayout.isStructurallyValid(readerItemInListZone))

        var fixedControlsReordered = ReaderToolbarLayout.defaultIdentifiers
        guard let listIndex = fixedControlsReordered.firstIndex(of: .macWikiListContents),
              let searchIndex = fixedControlsReordered.firstIndex(of: .macWikiSearch) else {
            return
        }
        fixedControlsReordered.swapAt(listIndex, searchIndex)
        #expect(!ReaderToolbarLayout.isStructurallyValid(fixedControlsReordered))
    }

    @Test func productionControllerKeepsNativeToolbarAvailableAcrossReaderStates() throws {
        let paneControllers = (0..<4).map { _ in NSViewController() }
        let splitController = WorkspaceSplitViewController(
            sidebarController: paneControllers[0],
            directoryController: paneControllers[1],
            readerController: paneControllers[2],
            inspectorController: paneControllers[3],
            initialSidebarWidth: 220,
            initialDirectoryWidth: 320,
            initialInspectorWidth: 320
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_600, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = splitController

        let appState = AppState(persistenceMode: .ephemeral)
        let sidebarSearchModel = SidebarSearchSurfaceModel()
        let environment = ReaderToolbarEnvironment(
            appState: appState,
            modelContext: try makeInMemoryModelContext(),
            openURL: OpenURLAction { _ in .handled },
            accessibilityPersonalization: .standard,
            sidebarSearchModel: sidebarSearchModel
        )
        let controller = ReaderToolbarController(
            splitController: splitController,
            environment: environment
        )
        controller.installIfPossible()

        #expect(window.toolbar === controller.toolbar)
        #expect(controller.toolbar.isVisible)
        #expect(window.toolbarStyle == .unified)

        try expectFixedWorkspaceControlsEnabled(in: controller.toolbar)
        try expectArticleControlsDisabled(in: controller.toolbar)

        appState.openArticle(Article(id: "toolbar-article", title: "Toolbar Article"))
        let articleTabID = try #require(appState.activeTabId)
        controller.update(environment: environment)
        #expect(window.toolbar === controller.toolbar)
        #expect(controller.toolbar.isVisible)
        #expect(try #require(item(.macWikiArticleState, in: controller.toolbar)).isEnabled)
        #expect(try #require(item(.macWikiFind, in: controller.toolbar)).isEnabled)
        #expect(try #require(item(.macWikiStyle, in: controller.toolbar)).isEnabled)
        #expect(try #require(item(.macWikiPageViews, in: controller.toolbar)).isEnabled)
        #expect(try #require(item(.macWikiOpenInBrowser, in: controller.toolbar)).isEnabled)
        #expect(try #require(item(.macWikiShare, in: controller.toolbar)).isEnabled)

        #expect(controller.toolbar.identifier == .macWikiReaderScoped)
        #expect(controller.toolbar.displayMode == .iconOnly)
        #expect(controller.toolbar.allowsUserCustomization)
        #expect(controller.toolbar.autosavesConfiguration)
        #expect(!controller.toolbar.allowsDisplayModeCustomization)
        #expect(ReaderToolbarLayout.isStructurallyValid(controller.toolbar.itemIdentifiers))

        for boundary in [
            NSToolbarItem.Identifier.macWikiSidebarDirectoryBoundary,
            .macWikiDirectoryReaderBoundary,
            .macWikiReaderInspectorBoundary
        ] {
            #expect(item(boundary, in: controller.toolbar) is NSTrackingSeparatorToolbarItem)
        }
        #expect(item(.macWikiHistory, in: controller.toolbar) is NSToolbarItemGroup)
        #expect(item(.macWikiArticleState, in: controller.toolbar) is NSToolbarItemGroup)
        #expect(item(.macWikiSearch, in: controller.toolbar) is NSSearchToolbarItem)
        #expect(item(.toggleSidebar, in: controller.toolbar)?.image != nil)
        #expect(item(.toggleInspector, in: controller.toolbar)?.image != nil)
        #expect(
            (item(.macWikiHistory, in: controller.toolbar) as? NSToolbarItemGroup)?
                .controlRepresentation == .automatic
        )
        #expect(
            (item(.macWikiArticleState, in: controller.toolbar) as? NSToolbarItemGroup)?
                .controlRepresentation == .automatic
        )
        #expect(item(.macWikiShare, in: controller.toolbar) is NSSharingServicePickerToolbarItem)

        let searchField = try #require(
            (item(.macWikiSearch, in: controller.toolbar) as? NSSearchToolbarItem)?.searchField
        )
        searchField.stringValue = "Ada Lovelace"
        controller.controlTextDidChange(Notification(
            name: NSControl.textDidChangeNotification,
            object: searchField
        ))
        #expect(sidebarSearchModel.searchCoordinator.searchText == "Ada Lovelace")
        #expect(appState.showSearch)
        sidebarSearchModel.searchCoordinator.clearSearch()
        controller.update(environment: environment)
        #expect(searchField.stringValue.isEmpty)
        for identifier in ReaderToolbarLayout.fixedIdentifiers {
            #expect(
                try #require(item(identifier, in: controller.toolbar))
                    .visibilityPriority.rawValue
                    >= NSToolbarItem.VisibilityPriority.high.rawValue
            )
        }
        for identifier in [
            NSToolbarItem.Identifier.macWikiStyle,
            .macWikiPageViews,
            .macWikiOpenInBrowser,
            .macWikiShare
        ] {
            #expect(
                try #require(item(identifier, in: controller.toolbar)).visibilityPriority == .low
            )
        }
        for identifier in [
            NSToolbarItem.Identifier.macWikiHistory,
            .macWikiArticleState,
            .macWikiFind
        ] {
            #expect(
                try #require(item(identifier, in: controller.toolbar)).visibilityPriority == .standard
            )
        }
        #expect(
            controller.toolbarImmovableItemIdentifiers(controller.toolbar)
                == ReaderToolbarLayout.fixedIdentifiers
        )

        controller.toolbar.isVisible = false
        appState.showDiscoverPage()
        controller.update(environment: environment)
        #expect(window.toolbar === controller.toolbar)
        #expect(!controller.toolbar.isVisible)
        try expectFixedWorkspaceControlsEnabled(in: controller.toolbar)
        try expectArticleControlsDisabled(in: controller.toolbar)

        #expect(appState.selectTab(articleTabID))
        controller.update(environment: environment)
        #expect(window.toolbar === controller.toolbar)
        #expect(!controller.toolbar.isVisible)

        controller.invalidate()
        #expect(window.toolbar == nil)
        #expect(controller.toolbar.delegate == nil)
    }

    private func expectFixedWorkspaceControlsEnabled(in toolbar: NSToolbar) throws {
        for identifier in [
            NSToolbarItem.Identifier.toggleSidebar,
            .macWikiListContents,
            .macWikiSearch,
            .toggleInspector
        ] {
            #expect(try #require(item(identifier, in: toolbar)).isEnabled)
        }
    }

    private func expectArticleControlsDisabled(in toolbar: NSToolbar) throws {
        for identifier in [
            NSToolbarItem.Identifier.macWikiArticleState,
            .macWikiFind,
            .macWikiStyle,
            .macWikiPageViews,
            .macWikiOpenInBrowser,
            .macWikiShare
        ] {
            #expect(!((try #require(item(identifier, in: toolbar))).isEnabled))
        }
    }

    private func item(
        _ identifier: NSToolbarItem.Identifier,
        in toolbar: NSToolbar
    ) -> NSToolbarItem? {
        toolbar.items.first { $0.itemIdentifier == identifier }
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            Label.self,
            ReadingList.self,
            SavedArticle.self,
            Highlight.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
