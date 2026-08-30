import AppKit
import SwiftData
import SwiftUI
import Testing

@testable import MacWiki

@Suite("Native workspace toolbar", .serialized)
@MainActor
struct WorkspaceToolbarControllerTests {
    @Test("native items are ordered inside three split-tracking boundaries")
    func nativeItemsTrackEveryWorkspaceDivider() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)

        #expect(toolbar.identifier == WorkspaceToolbarLayout.toolbarIdentifier)
        #expect(toolbar.items.map(\.itemIdentifier) == WorkspaceToolbarLayout.defaultItemIdentifiers)
        #expect(!toolbar.allowsUserCustomization)
        #expect(!toolbar.allowsDisplayModeCustomization)
        #expect(!toolbar.autosavesConfiguration)

        let separators = toolbar.items.compactMap { $0 as? NSTrackingSeparatorToolbarItem }
        #expect(separators.count == 3)
        #expect(separators.map(\.dividerIndex) == [0, 1, 2])
        #expect(separators.allSatisfy { $0.splitView === fixture.splitController.splitView })

        let rightBoundary = try #require(
            toolbar.items.firstIndex { $0.itemIdentifier == .inspectorTrackingSeparator }
        )
        let inspectorModesIndex = try #require(
            toolbar.items.firstIndex { $0.itemIdentifier == .workspaceInspectorModes }
        )
        for identifier in WorkspaceToolbarLayout.readerItemIdentifiers {
            let index = try #require(toolbar.items.firstIndex { $0.itemIdentifier == identifier })
            #expect(index < rightBoundary)
        }
        #expect(inspectorModesIndex == rightBoundary + 1)

        let inspectorModes = try #require(
            toolbar.items[inspectorModesIndex] as? NSToolbarItemGroup
        )
        #expect(inspectorModes.controlRepresentation == .expanded)
        #expect(inspectorModes.selectionMode == .selectOne)
        #expect(inspectorModes.selectedIndex == 0)
        #expect(inspectorModes.subitems.map(\.label) == InspectorMode.allCases.map(\.rawValue))
        if #available(macOS 27, *) {
            #expect(inspectorModes.value(forKey: "role") as? Int == 1)
        }

        for item in toolbar.items where WorkspaceToolbarLayout.readerItemIdentifiers.contains(item.itemIdentifier)
                && item.itemIdentifier != .toggleInspector {
            #expect(item.view == nil)
            #expect(item.isBordered)
            #expect(item.style == .plain)
            #expect(item.image != nil)
            #expect(item.toolTip?.isEmpty == false)
        }
        let inspectorToggle = try #require(
            toolbar.items.first { $0.itemIdentifier == .toggleInspector }
        )
        let inspectorToggleButton = try #require(inspectorToggle.view as? NSButton)
        #expect(inspectorToggle.image != nil)
        #expect(inspectorToggleButton.target === fixture.splitController)
        #expect(inspectorToggleButton.action == #selector(NSSplitViewController.toggleInspector(_:)))
    }

    @Test("Inspector mode switches preserve toolbar identity and item geometry graph")
    func inspectorModesPerformNoToolbarMutation() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        let toolbarIdentity = ObjectIdentifier(toolbar)
        let itemIdentities = toolbar.items.map(ObjectIdentifier.init)
        let itemOrder = toolbar.items.map(\.itemIdentifier)
        let readItem = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceReadState }
        )
        let readImage = try #require(readItem.image)
        let readPresentation = (readItem.label, readItem.toolTip, readItem.isEnabled)
        let inspectorBoundary = try #require(
            toolbar.items.first { $0.itemIdentifier == .inspectorTrackingSeparator }
        )
        let inspectorModes = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceInspectorModes }
                as? NSToolbarItemGroup
        )
        let inspectorModesIdentity = ObjectIdentifier(inspectorModes)

        for index in 0..<50 {
            let mode = InspectorMode.allCases[
                index % InspectorMode.allCases.count
            ]
            fixture.appState.inspectorMode = mode
            fixture.toolbarController.update(
                configuration: fixture.makeConfiguration()
            )

            #expect(ObjectIdentifier(try #require(fixture.window.toolbar)) == toolbarIdentity)
            #expect(toolbar.items.map(ObjectIdentifier.init) == itemIdentities)
            #expect(toolbar.items.map(\.itemIdentifier) == itemOrder)
            #expect(ObjectIdentifier(inspectorModes) == inspectorModesIdentity)
            #expect(inspectorModes.selectedIndex == InspectorMode.allCases.firstIndex(of: mode))
            #expect(readItem.image === readImage)
            #expect((readItem.label, readItem.toolTip, readItem.isEnabled) == readPresentation)
        }

        inspectorModes.selectedIndex = try #require(
            InspectorMode.allCases.firstIndex(of: .references)
        )
        let action = try #require(inspectorModes.action)
        let referencesSubitem = try #require(inspectorModes.subitems.last)
        #expect(NSApp.sendAction(action, to: inspectorModes.target, from: referencesSubitem))
        #expect(fixture.appState.inspectorMode == .references)

        fixture.appState.inspectorVisible = false
        fixture.toolbarController.update(configuration: fixture.makeConfiguration())
        #expect(inspectorModes.isEnabled)
        #expect(!inspectorModes.isHidden)
        #expect(!inspectorBoundary.isHidden)
        fixture.toolbarController.setInspectorPlaneVisible(false)
        #expect(!inspectorModes.isEnabled)
        #expect(inspectorModes.isHidden)
        #expect(!toolbar.items.contains { $0 === inspectorBoundary })
        #expect(!toolbar.items.contains { $0.itemIdentifier == .inspectorTrackingSeparator })
        #expect(ObjectIdentifier(inspectorModes) == inspectorModesIdentity)

        fixture.appState.inspectorMode = .info
        fixture.toolbarController.update(configuration: fixture.makeConfiguration())
        #expect(!inspectorModes.isEnabled)
        #expect(inspectorModes.isHidden)
        #expect(!toolbar.items.contains { $0.itemIdentifier == .inspectorTrackingSeparator })
        #expect(inspectorModes.selectedIndex == 0)
        #expect(ObjectIdentifier(inspectorModes) == inspectorModesIdentity)

        fixture.appState.inspectorVisible = true
        fixture.toolbarController.update(configuration: fixture.makeConfiguration())
        #expect(!inspectorModes.isEnabled)
        #expect(inspectorModes.isHidden)
        #expect(!toolbar.items.contains { $0.itemIdentifier == .inspectorTrackingSeparator })
        fixture.toolbarController.setInspectorPlaneVisible(true)
        #expect(inspectorModes.isEnabled)
        #expect(!inspectorModes.isHidden)
        let restoredBoundary = try #require(
            toolbar.items.first { $0.itemIdentifier == .inspectorTrackingSeparator }
                as? NSTrackingSeparatorToolbarItem
        )
        #expect(restoredBoundary.dividerIndex == 2)
        #expect(restoredBoundary.splitView === fixture.splitController.splitView)
        #expect(ObjectIdentifier(inspectorModes) == inspectorModesIdentity)
    }

    @Test("Read action updates native presentation and persistence in both directions")
    func readActionUpdatesPresentationAndState() throws {
        let article = Article(id: "ada", title: "Ada Lovelace")
        let fixture = try makeFixture(article: article)
        defer { fixture.tearDown() }

        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        let readItem = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceReadState }
        )
        #expect(readItem.label == "Mark as Read")
        #expect(readItem.image?.accessibilityDescription == "Mark as Read")
        #expect(fixture.appState.currentArticle?.isRead == false)

        let action = try #require(readItem.action)
        #expect(NSApp.sendAction(action, to: readItem.target, from: readItem))

        #expect(fixture.appState.currentArticle?.isRead == true)
        #expect(readItem.label == "Mark as Unread")
        #expect(readItem.toolTip == "Mark as Unread")
        #expect(readItem.image?.accessibilityDescription == "Mark as Unread")
        #expect(readItem.possibleLabels == ["Mark as Read", "Mark as Unread"])
        let persistedReadState = try #require(
            ReadStateSync.fetchArticleState(
                forURLString: article.url.absoluteString,
                in: fixture.modelContext
            )
        )
        #expect(persistedReadState.isRead)
        #expect(persistedReadState.readingProgress == 1)

        #expect(NSApp.sendAction(action, to: readItem.target, from: readItem))
        #expect(fixture.appState.currentArticle?.isRead == false)
        #expect(readItem.label == "Mark as Read")
        #expect(readItem.toolTip == "Mark as Read")
        #expect(readItem.image?.accessibilityDescription == "Mark as Read")
        #expect(persistedReadState.isRead == false)
    }

    @Test("Inspector action starts one native split and toolbar-plane transition")
    func inspectorActionUsesNativeSplitTransition() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        fixture.splitController.onInspectorToolbarVisibilityChange = {
            fixture.toolbarController.setInspectorPlaneVisible($0)
        }
        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        let toggle = try #require(
            toolbar.items.first { $0.itemIdentifier == .toggleInspector }
        )
        let modes = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceInspectorModes }
        )
        let boundary = try #require(
            toolbar.items.first { $0.itemIdentifier == .inspectorTrackingSeparator }
        )

        let toggleButton = try #require(toggle.view as? NSButton)
        #expect(NSApp.sendAction(try #require(toggleButton.action), to: toggleButton.target, from: toggleButton))
        #expect(modes.isHidden)
        #expect(!toolbar.items.contains { $0 === boundary })
    }

    @Test("Divider collapse keeps Inspector toolbar chrome attached to the pane")
    func dividerCollapseUpdatesInspectorToolbarPlane() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        fixture.splitController.onInspectorToolbarVisibilityChange = {
            fixture.toolbarController.setInspectorPlaneVisible($0)
        }
        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        let modes = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceInspectorModes }
        )
        let boundary = try #require(
            toolbar.items.first { $0.itemIdentifier == .inspectorTrackingSeparator }
        )
        let inspectorItem = fixture.splitController.splitViewItems[3]

        inspectorItem.isCollapsed = true
        #expect(modes.isHidden)
        #expect(!toolbar.items.contains { $0 === boundary })

        inspectorItem.isCollapsed = false
        #expect(!modes.isHidden)
        #expect(toolbar.items.contains { $0.itemIdentifier == .inspectorTrackingSeparator })
    }

    @Test("sharing and validation follow the live article and navigation lock")
    func sharingAndValidationFollowLiveState() throws {
        let article = Article(id: "ada", title: "Ada Lovelace")
        let fixture = try makeFixture(article: article)
        defer { fixture.tearDown() }
        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        let shareItem = try #require(
            toolbar.items.first { $0.itemIdentifier == .workspaceShare }
                as? NSSharingServicePickerToolbarItem
        )

        #expect(fixture.toolbarController.items(for: shareItem).compactMap { $0 as? URL } == [article.url])
        #expect(shareItem.isEnabled)

        let target = Article(id: "charles", title: "Charles Babbage")
        fixture.appState.startWikiHop(mode: .chill, start: article, target: target)
        fixture.toolbarController.update(configuration: fixture.makeConfiguration())
        for item in toolbar.items where WorkspaceToolbarLayout.readerItemIdentifiers.contains(item.itemIdentifier) {
            if item.itemIdentifier == .toggleInspector {
                #expect(item.isEnabled)
            } else {
                #expect(!item.isEnabled)
            }
        }

        let emptyFixture = try makeFixture()
        defer { emptyFixture.tearDown() }
        emptyFixture.toolbarController.install(on: emptyFixture.window)
        let emptyToolbar = try #require(emptyFixture.window.toolbar)
        let emptyShareItem = try #require(
            emptyToolbar.items.first { $0.itemIdentifier == .workspaceShare }
                as? NSSharingServicePickerToolbarItem
        )
        #expect(emptyFixture.toolbarController.items(for: emptyShareItem).isEmpty)
        for identifier in [
            NSToolbarItem.Identifier.workspaceSave,
            .workspaceReadState,
            .workspaceFind,
            .workspaceReaderStyle,
            .workspacePageViews,
            .workspaceOpenBrowser,
            .workspaceShare
        ] {
            #expect(emptyToolbar.items.first { $0.itemIdentifier == identifier }?.isEnabled == false)
        }
    }

    @Test("installation never replaces a foreign toolbar")
    func foreignToolbarIsNeverReplaced() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let sentinel = NSToolbar(identifier: "WorkspaceToolbarControllerTests.Foreign")
        fixture.window.toolbar = sentinel

        fixture.toolbarController.install(on: fixture.window)

        #expect(fixture.window.toolbar === sentinel)
    }

    @Test("repeat install is pointer-idempotent and teardown restores owned chrome")
    func repeatInstallAndOwnedTeardownAreSafe() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }
        let originalStyle = fixture.window.toolbarStyle
        let originalTitleVisibility = fixture.window.titleVisibility

        fixture.toolbarController.install(on: fixture.window)
        let toolbar = try #require(fixture.window.toolbar)
        fixture.toolbarController.install(on: fixture.window)
        #expect(fixture.window.toolbar === toolbar)

        fixture.toolbarController.invalidate()
        #expect(fixture.window.toolbar == nil)
        #expect(fixture.window.toolbarStyle == originalStyle)
        #expect(fixture.window.titleVisibility == originalTitleVisibility)
    }

    @Test("external removal safely refuses popovers and preserves the chrome baseline")
    func externalRemovalCanReinstallWithoutLosingChromeBaseline() throws {
        let article = Article(id: "ada", title: "Ada Lovelace")
        let fixture = try makeFixture(article: article)
        defer { fixture.tearDown() }
        let originalStyle = fixture.window.toolbarStyle
        let originalTitleVisibility = fixture.window.titleVisibility

        fixture.toolbarController.install(on: fixture.window)
        fixture.window.toolbar = nil
        fixture.appState.requestReaderStylePresentation()
        fixture.toolbarController.update(configuration: fixture.makeConfiguration())
        #expect(fixture.window.toolbar == nil)

        fixture.toolbarController.install(on: fixture.window)
        #expect(fixture.window.toolbar?.identifier == WorkspaceToolbarLayout.toolbarIdentifier)
        fixture.toolbarController.invalidate()
        #expect(fixture.window.toolbar == nil)
        #expect(fixture.window.toolbarStyle == originalStyle)
        #expect(fixture.window.titleVisibility == originalTitleVisibility)
    }

    @Test("teardown leaves a subsequently installed foreign toolbar untouched")
    func teardownDoesNotTouchAnotherOwner() throws {
        let fixture = try makeFixture()
        defer { fixture.tearDown() }

        fixture.toolbarController.install(on: fixture.window)
        let foreign = NSToolbar(identifier: "WorkspaceToolbarControllerTests.Replacement")
        fixture.window.toolbar = foreign

        fixture.toolbarController.invalidate()
        #expect(fixture.window.toolbar === foreign)
    }

    private func makeFixture(article: Article? = nil) throws -> ToolbarFixture {
        let appState = AppState(persistenceMode: .ephemeral)
        if let article {
            let tab = ArticleTab(article: article)
            appState.openTabs = [tab]
            appState.activeTabId = tab.id
        }

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ReadingList.self,
            SavedArticle.self,
            ArticleState.self,
            Highlight.self,
            ArticleNote.self,
            Label.self,
            Tag.self,
            Area.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)
        let openURL = OpenURLAction { _ in .handled }

        let lists = paneController()
        let directory = paneController()
        let reader = paneController()
        let inspector = paneController()
        let splitController = AppKitWorkspaceNavigationController(
            listsController: lists,
            directoryController: directory,
            readerController: reader,
            inspectorController: inspector,
            initialListsWidth: 220,
            initialDirectoryWidth: 320,
            initialInspectorWidth: 320
        )
        _ = splitController.view
        let window = NSWindow(contentViewController: splitController)
        window.setContentSize(NSSize(width: 1_500, height: 800))
        splitController.view.layoutSubtreeIfNeeded()

        let makeConfiguration = {
            WorkspaceToolbarConfiguration(
                appState: appState,
                modelContext: modelContext,
                openURL: openURL
            )
        }
        let toolbarController = WorkspaceToolbarController(
            splitController: splitController,
            configuration: makeConfiguration()
        )
        return ToolbarFixture(
            appState: appState,
            modelContext: modelContext,
            splitController: splitController,
            window: window,
            toolbarController: toolbarController,
            makeConfiguration: makeConfiguration
        )
    }

    private func paneController() -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: .zero)
        return controller
    }
}

@MainActor
private struct ToolbarFixture {
    let appState: AppState
    let modelContext: ModelContext
    let splitController: AppKitWorkspaceNavigationController
    let window: NSWindow
    let toolbarController: WorkspaceToolbarController
    let makeConfiguration: () -> WorkspaceToolbarConfiguration

    func tearDown() {
        toolbarController.invalidate()
        window.close()
    }
}
