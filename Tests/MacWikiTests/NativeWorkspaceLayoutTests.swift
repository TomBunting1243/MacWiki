import AppKit
import Foundation
import Testing

@testable import MacWiki

@Suite(.serialized)
@MainActor
struct NativeWorkspaceLayoutTests {
    @Test func appStateRoundTripsEveryIndependentNavigationCombination() {
        let appState = AppState(persistenceMode: .ephemeral)
        let combinations = [
            WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: true),
            WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: false),
            WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: true),
            WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: false)
        ]

        for visibility in combinations {
            appState.setNavigationColumnVisibility(
                listsVisible: visibility.listsVisible,
                directoryVisible: visibility.directoryVisible
            )

            #expect(appState.listsSidebarVisible == visibility.listsVisible)
            #expect(appState.directoryColumnVisible == visibility.directoryVisible)
        }
    }

    @Test func appKitControllerUsesSemanticNativePaneRolesAndSizing() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        let items = fixture.controller.splitViewItems
        #expect(items.count == 3)
        #expect(items[0].behavior == .sidebar)
        #expect(items[1].behavior == .contentList)
        #expect(items[2].behavior == .default)

        #expect(items[0].canCollapse)
        #expect(items[1].canCollapse)
        #expect(!items[2].canCollapse)
        #expect(!items[0].canCollapseFromWindowResize)
        #expect(!items[1].canCollapseFromWindowResize)
        #expect(items[0].collapseBehavior == .preferResizingSiblingsWithFixedSplitView)
        #expect(items[1].collapseBehavior == .preferResizingSiblingsWithFixedSplitView)
        #expect(items[0].allowsFullHeightLayout)

        #expect(items[0].minimumThickness == MainWindowColumnWidth.sidebarRange.lowerBound)
        #expect(items[0].maximumThickness == MainWindowColumnWidth.sidebarRange.upperBound)
        #expect(items[1].minimumThickness == MainWindowColumnWidth.directoryRange.lowerBound)
        #expect(items[1].maximumThickness == MainWindowColumnWidth.directoryRange.upperBound)
        #expect(items[2].minimumThickness == 1)
        #expect(items[2].holdingPriority == .defaultLow)
    }

    @Test func appKitControllerSupportsEveryIndependentVisibilityCombination() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        let combinations = [
            WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: true),
            WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: false),
            WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: true),
            WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: false)
        ]

        for visibility in combinations {
            fixture.controller.setPaneVisibility(
                listsVisible: visibility.listsVisible,
                directoryVisible: visibility.directoryVisible,
                animated: false
            )
            layout(fixture)

            #expect(fixture.controller.splitViewItems[0].isCollapsed == !visibility.listsVisible)
            #expect(fixture.controller.splitViewItems[1].isCollapsed == !visibility.directoryVisible)
            #expect(!fixture.controller.splitViewItems[2].isCollapsed)
        }
    }

    @Test func readerControllerAndViewIdentitySurviveTwentyPaneToggleCycles() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        let readerController = fixture.reader
        let readerView = readerController.view

        for index in 0..<20 {
            fixture.controller.setPaneVisibility(
                listsVisible: index.isMultiple(of: 2),
                directoryVisible: index.isMultiple(of: 3),
                animated: false
            )
            layout(fixture)

            #expect(fixture.controller.splitViewItems[2].viewController === readerController)
            #expect(fixture.controller.splitViewItems[2].viewController.view === readerView)
            #expect(!fixture.controller.splitViewItems[2].isCollapsed)
        }
    }

    @Test func initialAuxiliaryWidthRestorationKeepsEveryPaneWithinItsNativeBounds() {
        let fixture = makeFixture(
            width: 1_500,
            initialListsWidth: 220,
            initialDirectoryWidth: 330
        )
        defer { fixture.tearDown() }
        layout(fixture)
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture)

        let items = fixture.controller.splitViewItems
        #expect(MainWindowColumnWidth.sidebarRange.contains(items[0].viewController.view.bounds.width))
        #expect(MainWindowColumnWidth.directoryRange.contains(items[1].viewController.view.bounds.width))
        #expect(items[2].viewController.view.bounds.width >= MainWindowLayout.minimumReaderWidth)
    }

    @Test func widthPersistenceWritesOnlyToTheInjectedDefaultsBoundary() async throws {
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        #expect(bridge.contains("widthDefaults: UserDefaults = MacWikiDefaults.current"))
        #expect(!bridge.contains("UserDefaults.standard"))
        #expect(bridge.contains("AppStorageKey.MainWindow.sidebarWidth"))
        #expect(bridge.contains("AppStorageKey.MainWindow.directoryWidth"))

        // This intentionally takes the adaptive-baseline path before either
        // pane is resized, matching a compact but valid application window.
        let fixture = makeFixture(width: 1_000)
        defer { fixture.tearDown() }
        layout(fixture)
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture)

        let sidebarKey = AppStorageKey.MainWindow.sidebarWidth
        let directoryKey = AppStorageKey.MainWindow.directoryWidth
        let standardSidebarBefore = UserDefaults.standard.object(forKey: sidebarKey) as? Double
        let standardDirectoryBefore = UserDefaults.standard.object(forKey: directoryKey) as? Double

        fixture.controller.splitView.setPosition(210, ofDividerAt: 0)
        fixture.controller.splitView.layoutSubtreeIfNeeded()
        let directoryOrigin = fixture.directory.view.convert(.zero, to: fixture.controller.splitView).x
        fixture.controller.splitView.setPosition(directoryOrigin + 300, ofDividerAt: 1)
        layout(fixture)

        fixture.controller.splitViewDidResizeSubviews(
            Notification(name: NSSplitView.didResizeSubviewsNotification, object: fixture.controller.splitView)
        )

        try await Task.sleep(for: .milliseconds(450))

        let persistedSidebarWidth = fixture.widthDefaults.object(forKey: sidebarKey) as? Double
        let persistedDirectoryWidth = fixture.widthDefaults.object(forKey: directoryKey) as? Double
        let expectedSidebarWidth = MainWindowColumnWidth.clampedStorageValue(
            fixture.lists.view.bounds.width,
            range: MainWindowColumnWidth.sidebarRange
        )
        let expectedDirectoryWidth = MainWindowColumnWidth.clampedStorageValue(
            fixture.directory.view.bounds.width,
            range: MainWindowColumnWidth.directoryRange
        )

        #expect(persistedSidebarWidth != nil)
        #expect(persistedDirectoryWidth != nil)
        #expect(abs((persistedSidebarWidth ?? 0) - (expectedSidebarWidth ?? 0)) < 1)
        #expect(abs((persistedDirectoryWidth ?? 0) - (expectedDirectoryWidth ?? 0)) < 1)

        #expect((UserDefaults.standard.object(forKey: sidebarKey) as? Double) == standardSidebarBefore)
        #expect((UserDefaults.standard.object(forKey: directoryKey) as? Double) == standardDirectoryBefore)
    }

    @Test func columnWidthStorageRejectsInvalidValuesAndClampsExtremes() {
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(260, range: MainWindowColumnWidth.inspectorRange) == 270)
    }

    private func makeFixture(
        width: CGFloat,
        initialListsWidth: CGFloat = 220,
        initialDirectoryWidth: CGFloat = 320
    ) -> WorkspaceFixture {
        let lists = makePaneController()
        let directory = makePaneController()
        let reader = makePaneController()

        let defaultsSuiteName = MacWikiDefaults.qaSuitePrefix
            + "NativeWorkspaceLayoutTests."
            + UUID().uuidString
        guard let widthDefaults = UserDefaults(suiteName: defaultsSuiteName) else {
            fatalError("Could not create isolated workspace-width defaults")
        }
        widthDefaults.removePersistentDomain(forName: defaultsSuiteName)

        let controller = AppKitWorkspaceNavigationController(
            listsController: lists,
            directoryController: directory,
            readerController: reader,
            initialListsWidth: initialListsWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            widthDefaults: widthDefaults
        )
        return WorkspaceFixture(
            controller: controller,
            size: NSSize(width: width, height: 800),
            lists: lists,
            directory: directory,
            reader: reader,
            widthDefaults: widthDefaults,
            defaultsSuiteName: defaultsSuiteName
        )
    }

    private func makePaneController() -> NSViewController {
        let controller = NSViewController()
        controller.view = NSView(frame: .zero)
        return controller
    }

    private func layout(_ fixture: WorkspaceFixture) {
        fixture.controller.view.frame = NSRect(origin: .zero, size: fixture.size)
        fixture.controller.splitView.frame = fixture.controller.view.bounds
        fixture.controller.splitView.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

@MainActor
private struct WorkspaceFixture {
    let controller: AppKitWorkspaceNavigationController
    let size: NSSize
    let lists: NSViewController
    let directory: NSViewController
    let reader: NSViewController
    let widthDefaults: UserDefaults
    let defaultsSuiteName: String

    func tearDown() {
        controller.view.removeFromSuperview()
        widthDefaults.removePersistentDomain(forName: defaultsSuiteName)
    }
}
