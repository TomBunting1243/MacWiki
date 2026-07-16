import AppKit
import Foundation
import Testing

@testable import MacWiki

@Suite(.serialized)
@MainActor
struct NativeWorkspaceLayoutTests {
    @Test func appStateRoundTripsEveryIndependentNavigationCombination() {
        let appState = AppState(persistenceMode: .ephemeral)
        for visibility in Self.everyAuxiliaryVisibilityCombination {
            appState.setNavigationColumnVisibility(
                listsVisible: visibility.listsVisible,
                directoryVisible: visibility.directoryVisible
            )
            appState.inspectorVisible = visibility.inspectorVisible

            #expect(appState.listsSidebarVisible == visibility.listsVisible)
            #expect(appState.directoryColumnVisible == visibility.directoryVisible)
            #expect(appState.inspectorVisible == visibility.inspectorVisible)
        }
    }

    @Test func appKitControllerUsesSemanticNativePaneRolesAndSizing() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        let items = fixture.controller.splitViewItems
        #expect(items.count == 4)
        #expect(items[0].behavior == .sidebar)
        #expect(items[1].behavior == .contentList)
        #expect(items[2].behavior == .default)
        #expect(items[3].behavior == .inspector)

        #expect(items[0].canCollapse)
        #expect(items[1].canCollapse)
        #expect(!items[2].canCollapse)
        #expect(items[3].canCollapse)
        #expect(items[0].canCollapseFromWindowResize)
        #expect(items[1].canCollapseFromWindowResize)
        #expect(!items[3].canCollapseFromWindowResize)
        #expect(items[0].collapseBehavior == .preferResizingSiblingsWithFixedSplitView)
        #expect(items[1].collapseBehavior == .preferResizingSiblingsWithFixedSplitView)
        #expect(items[3].collapseBehavior == .preferResizingSiblingsWithFixedSplitView)
        #expect(items[0].allowsFullHeightLayout)
        #expect(items[3].allowsFullHeightLayout)

        #expect(items[0].minimumThickness == MainWindowColumnWidth.sidebarRange.lowerBound)
        #expect(items[0].maximumThickness == MainWindowColumnWidth.sidebarRange.upperBound)
        #expect(items[1].minimumThickness == MainWindowColumnWidth.directoryRange.lowerBound)
        #expect(items[1].maximumThickness == MainWindowColumnWidth.directoryRange.upperBound)
        #expect(items[2].minimumThickness == MainWindowLayout.minimumCompactReaderWidth)
        #expect(items[2].holdingPriority == .defaultLow)
        #expect(items[3].minimumThickness == MainWindowColumnWidth.inspectorRange.lowerBound)
        #expect(items[3].maximumThickness == MainWindowColumnWidth.inspectorRange.upperBound)
    }

    @Test func readerAndInspectorChromeUseNativeTopAlignedSplitItemAccessories() {
        let readerAccessory = NSSplitViewItemAccessoryViewController()
        readerAccessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 36))
        let inspectorAccessory = NSSplitViewItemAccessoryViewController()
        inspectorAccessory.view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 36))
        let fixture = makeFixture(
            width: 1_500,
            readerAccessoryController: readerAccessory,
            inspectorAccessoryController: inspectorAccessory
        )
        defer { fixture.tearDown() }
        layout(fixture)

        #expect(fixture.controller.splitViewItems[0].topAlignedAccessoryViewControllers.isEmpty)
        #expect(fixture.controller.splitViewItems[1].topAlignedAccessoryViewControllers.isEmpty)
        #expect(fixture.controller.splitViewItems[2].topAlignedAccessoryViewControllers == [readerAccessory])
        #expect(fixture.controller.splitViewItems[3].topAlignedAccessoryViewControllers == [inspectorAccessory])
    }

    @Test func appKitControllerSupportsEveryIndependentVisibilityCombination() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        for visibility in Self.everyAuxiliaryVisibilityCombination {
            fixture.controller.setPaneVisibility(
                listsVisible: visibility.listsVisible,
                directoryVisible: visibility.directoryVisible,
                inspectorVisible: visibility.inspectorVisible,
                animated: false
            )
            layout(fixture)

            #expect(fixture.controller.splitViewItems[0].isCollapsed == !visibility.listsVisible)
            #expect(fixture.controller.splitViewItems[1].isCollapsed == !visibility.directoryVisible)
            #expect(!fixture.controller.splitViewItems[2].isCollapsed)
            #expect(fixture.controller.splitViewItems[3].isCollapsed == !visibility.inspectorVisible)
        }
    }

    @Test func standardResponderChainInspectorToggleControlsTheSemanticInspectorPane() {
        let fixture = makeFixture(width: 1_500)
        defer { fixture.tearDown() }
        layout(fixture)

        #expect(!fixture.controller.splitViewItems[3].isCollapsed)

        fixture.controller.toggleInspector(nil)
        layout(fixture)
        #expect(fixture.controller.splitViewItems[3].isCollapsed)

        fixture.controller.toggleInspector(nil)
        layout(fixture)
        #expect(!fixture.controller.splitViewItems[3].isCollapsed)
        #expect(!fixture.controller.splitViewItems[2].isCollapsed)
    }

    @Test func userInspectorToggleDuringAnotherPaneAnimationReconcilesNativeState() async {
        let fixture = makeFixture(width: 1_500)
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)

        var reportedVisibility: WorkspaceNavigationPaneVisibility?
        fixture.controller.onPaneVisibilityChange = { visibility in
            reportedVisibility = visibility
        }

        fixture.controller.setPaneVisibility(
            listsVisible: false,
            directoryVisible: true,
            inspectorVisible: true,
            animated: true
        )
        fixture.controller.toggleInspector(nil)

        let didReportVisibility = await waitForNativeCondition(timeout: 3) {
            reportedVisibility != nil
        }
        #expect(didReportVisibility)
        layout(fixture)

        #expect(fixture.controller.splitViewItems[3].isCollapsed)
        #expect(reportedVisibility?.listsVisible == false)
        #expect(reportedVisibility?.directoryVisible == true)
        #expect(reportedVisibility?.inspectorVisible == false)
    }

    @Test func compactWindowYieldsLeadingNavigationPanesBeforeCrushingReader() async {
        let fixture = makeFixture(width: 1_500)
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)

        window.setContentSize(NSSize(width: MainWindowLayout.minimumWindowWidth, height: 800))
        window.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()

        let didSettle = await waitForNativeCondition(timeout: 3) {
            let items = fixture.controller.splitViewItems
            return items[0].isCollapsed || items[1].isCollapsed
        }
        let items = fixture.controller.splitViewItems
        #expect(didSettle)
        #expect(items[0].isCollapsed || items[1].isCollapsed)
        #expect(!items[2].isCollapsed)
        #expect(items[2].viewController.view.bounds.width >= MainWindowLayout.minimumCompactReaderWidth)
        #expect(!items[3].isCollapsed)
    }

    @Test func transientNarrowFrameCannotRatchetLeadingPanesClosedDuringWideResize() async {
        let fixture = makeFixture(width: 1_500)
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)
        fixture.controller.setPaneVisibility(
            listsVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )

        var reportedVisibility: WorkspaceNavigationPaneVisibility?
        fixture.controller.onPaneVisibilityChange = { visibility in
            reportedVisibility = visibility
        }

        // Model the intermediate layout AX/AppKit can expose while applying a
        // larger target size: the compact frame must never become user intent.
        window.setContentSize(NSSize(width: 760, height: 800))
        window.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 1_760, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()

        let didSettle = await waitForNativeCondition(timeout: 3) {
            let items = fixture.controller.splitViewItems
            return items.count == 4
                && !items[0].isCollapsed
                && !items[1].isCollapsed
                && !items[2].isCollapsed
                && !items[3].isCollapsed
        }

        #expect(didSettle)
        #expect(reportedVisibility == nil)
    }

    @Test func firstWindowAttachmentPreservesRequestedFourPaneVisibility() async {
        let fixture = makeFixture(width: 1_800)
        fixture.controller.setPaneVisibility(
            listsVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        window.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()

        let didSettle = await waitForNativeCondition(timeout: 3) {
            fixture.controller.splitViewItems.allSatisfy { !$0.isCollapsed }
        }
        #expect(didSettle)
    }

    @Test func paneCommandDuringResizeSupersedesTheGeometrySnapshot() async {
        let fixture = makeFixture(width: 1_500)
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)

        window.setContentSize(NSSize(width: 1_760, height: 900))
        window.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()
        fixture.controller.setPaneVisibility(
            listsVisible: false,
            directoryVisible: true,
            inspectorVisible: false,
            animated: false
        )

        let didSettle = await waitForNativeCondition(timeout: 3) {
            let items = fixture.controller.splitViewItems
            return items[0].isCollapsed
                && !items[1].isCollapsed
                && !items[2].isCollapsed
                && items[3].isCollapsed
        }
        try? await Task.sleep(for: .milliseconds(180))

        let items = fixture.controller.splitViewItems
        #expect(didSettle)
        #expect(items[0].isCollapsed)
        #expect(!items[1].isCollapsed)
        #expect(!items[2].isCollapsed)
        #expect(items[3].isCollapsed)
    }

    @Test func detachedWindowCannotLeaveGeometryReconciliationPermanentlyPending() async {
        let fixture = makeFixture(width: 1_500)
        var window: NSWindow? = NSWindow(contentViewController: fixture.controller)
        window?.setContentSize(fixture.size)
        layout(fixture)

        window?.setContentSize(NSSize(width: 1_760, height: 900))
        window?.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()
        window?.contentViewController = NSViewController()
        window?.close()
        window = nil
        try? await Task.sleep(for: .milliseconds(180))

        let replacement = NSWindow(contentViewController: fixture.controller)
        defer {
            replacement.close()
            fixture.tearDown()
        }
        replacement.setContentSize(
            NSSize(width: MainWindowLayout.minimumWindowWidth, height: 800)
        )
        replacement.contentView?.layoutSubtreeIfNeeded()
        fixture.controller.view.layoutSubtreeIfNeeded()

        let didAdapt = await waitForNativeCondition(timeout: 3) {
            let items = fixture.controller.splitViewItems
            return items[0].isCollapsed || items[1].isCollapsed
        }
        #expect(didAdapt)
        #expect(!fixture.controller.splitViewItems[2].isCollapsed)
    }

    @Test func compactWindowPreservesTheLeadingPaneTheUserExplicitlyReveals() async {
        let fixture = makeFixture(width: MainWindowLayout.minimumWindowWidth)
        fixture.controller.setPaneVisibility(
            listsVisible: false,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)
        _ = await waitForNativeCondition(timeout: 3) {
            let items = fixture.controller.splitViewItems
            return items[0].isCollapsed
                && !items[1].isCollapsed
                && !items[3].isCollapsed
        }

        var reportedVisibility: WorkspaceNavigationPaneVisibility?
        fixture.controller.onPaneVisibilityChange = { visibility in
            reportedVisibility = visibility
        }
        fixture.controller.setPaneVisibility(
            listsVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture)

        let items = fixture.controller.splitViewItems
        #expect(!items[0].isCollapsed)
        #expect(items[1].isCollapsed)
        #expect(!items[2].isCollapsed)
        #expect(!items[3].isCollapsed)
        #expect(reportedVisibility?.listsVisible == true)
        #expect(reportedVisibility?.directoryVisible == false)
        #expect(reportedVisibility?.inspectorVisible == true)
    }

    @Test func supportedWindowMinimumCanPresentEitherLeadingPaneWithInspector() {
        let minimum = MainWindowLayout.minimumWindowWidth
        #expect(minimum >= MainWindowLayout.minimumCompactContentWidth(
            listsSidebarVisible: true,
            directoryVisible: false,
            inspectorVisible: true
        ))
        #expect(minimum >= MainWindowLayout.minimumCompactContentWidth(
            listsSidebarVisible: false,
            directoryVisible: true,
            inspectorVisible: true
        ))
    }

    @Test func fixedToolbarTargetsNestedWorkspaceInspectorAndTracksItsDivider() throws {
        let fixture = makeFixture(width: 1_500)
        let host = NSViewController()
        host.view = NSView(frame: NSRect(origin: .zero, size: fixture.size))
        host.addChild(fixture.controller)
        host.view.addSubview(fixture.controller.view)
        fixture.controller.view.frame = host.view.bounds

        let window = NSWindow(contentViewController: host)
        let toolbar = NSToolbar(identifier: "NativeWorkspaceLayoutTests.Toolbar")
        window.toolbar = toolbar
        let priorResponder = InspectorActionRecorderResponder()
        window.nextResponder = priorResponder
        let policy = FixedWindowToolbarPolicyView(
            installsInspectorSection: true,
            relaysNestedWorkspaceInspector: true
        )
        host.view.addSubview(policy)
        defer {
            window.close()
            fixture.tearDown()
        }

        layout(fixture)
        WorkspaceSplitControllerRegistry.register(fixture.controller, in: window)
        #expect(WorkspaceSplitControllerRegistry.controller(in: window) === fixture.controller)
        policy.enforcePolicy()

        let toggleItem = try #require(toolbar.items.first(where: {
            $0.itemIdentifier == .toggleInspector
        }))
        let trackingItem = try #require(toolbar.items.first(where: {
            $0.itemIdentifier == .inspectorTrackingSeparator
        }) as? NSTrackingSeparatorToolbarItem)
        let toggleAction = try #require(toggleItem.action)
        let responder = try #require(window.nextResponder as? WorkspaceInspectorResponder)
        #expect(toggleItem.target == nil)
        #expect(toggleAction == #selector(NSSplitViewController.toggleInspector(_:)))
        #expect(responder.controller === fixture.controller)
        #expect(trackingItem.splitView === fixture.controller.splitView)
        #expect(trackingItem.dividerIndex == 2)

        #expect(window.tryToPerform(toggleAction, with: nil))
        #expect(fixture.controller.splitViewItems[3].isCollapsed)
        #expect(priorResponder.invocationCount == 0)
        #expect(window.tryToPerform(toggleAction, with: nil))
        #expect(!fixture.controller.splitViewItems[3].isCollapsed)
        #expect(priorResponder.invocationCount == 0)

        policy.removeFromSuperview()
        #expect(window.nextResponder === priorResponder)
        #expect(window.tryToPerform(toggleAction, with: nil))
        #expect(priorResponder.invocationCount == 1)
    }

    @Test func fixedToolbarLeavesArticleWindowInspectorResponderUntouched() throws {
        let host = NSViewController()
        host.view = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        let window = NSWindow(contentViewController: host)
        let toolbar = NSToolbar(identifier: "NativeWorkspaceLayoutTests.ArticleToolbar")
        window.toolbar = toolbar
        let articleInspectorResponder = InspectorActionRecorderResponder()
        window.nextResponder = articleInspectorResponder
        let policy = FixedWindowToolbarPolicyView(installsInspectorSection: true)
        host.view.addSubview(policy)
        defer {
            window.close()
        }

        policy.enforcePolicy()

        let toggleItem = try #require(toolbar.items.first(where: {
            $0.itemIdentifier == .toggleInspector
        }))
        let toggleAction = try #require(toggleItem.action)
        #expect(toggleItem.target == nil)
        #expect(toggleAction == #selector(NSSplitViewController.toggleInspector(_:)))
        #expect(window.nextResponder === articleInspectorResponder)
        #expect(!(window.nextResponder is WorkspaceInspectorResponder))

        #expect(window.tryToPerform(toggleAction, with: nil))
        #expect(articleInspectorResponder.invocationCount == 1)
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
                inspectorVisible: index.isMultiple(of: 5),
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
            initialDirectoryWidth: 330,
            initialInspectorWidth: 310
        )
        defer { fixture.tearDown() }
        layout(fixture)
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture)

        let items = fixture.controller.splitViewItems
        #expect(MainWindowColumnWidth.sidebarRange.contains(items[0].viewController.view.bounds.width))
        #expect(MainWindowColumnWidth.directoryRange.contains(items[1].viewController.view.bounds.width))
        #expect(items[2].viewController.view.bounds.width >= MainWindowLayout.minimumReaderWidth)
        #expect(MainWindowColumnWidth.inspectorRange.contains(items[3].viewController.view.bounds.width))
    }

    @Test func widthPersistenceWritesOnlyToTheInjectedDefaultsBoundary() async throws {
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        #expect(bridge.contains("widthDefaults: UserDefaults = MacWikiDefaults.current"))
        #expect(!bridge.contains("UserDefaults.standard"))
        #expect(bridge.contains("AppStorageKey.MainWindow.sidebarWidth"))
        #expect(bridge.contains("AppStorageKey.MainWindow.directoryWidth"))
        #expect(bridge.contains("AppStorageKey.MainWindow.inspectorWidth"))

        // This width is above the all-pane adaptive minimum but below the sum
        // of the three ideal widths, exercising persistence from valid native
        // split geometry instead of depending on exact ideal-width rounding.
        let fixture = makeFixture(width: 1_300)
        fixture.controller.setPaneVisibility(
            listsVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        let window = NSWindow(contentViewController: fixture.controller)
        defer {
            window.close()
            fixture.tearDown()
        }
        window.setContentSize(fixture.size)
        layout(fixture)
        let didSettle = await waitForNativeCondition(timeout: 3) {
            fixture.controller.splitViewItems.allSatisfy { !$0.isCollapsed }
        }
        #expect(didSettle)
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture)

        let sidebarKey = AppStorageKey.MainWindow.sidebarWidth
        let directoryKey = AppStorageKey.MainWindow.directoryWidth
        let inspectorKey = AppStorageKey.MainWindow.inspectorWidth
        let standardSidebarBefore = UserDefaults.standard.object(forKey: sidebarKey) as? Double
        let standardDirectoryBefore = UserDefaults.standard.object(forKey: directoryKey) as? Double
        let standardInspectorBefore = UserDefaults.standard.object(forKey: inspectorKey) as? Double

        fixture.controller.splitView.setPosition(210, ofDividerAt: 0)
        fixture.controller.splitView.layoutSubtreeIfNeeded()
        let directoryOrigin = fixture.directory.view.convert(.zero, to: fixture.controller.splitView).x
        fixture.controller.splitView.setPosition(directoryOrigin + 300, ofDividerAt: 1)
        fixture.controller.splitView.setPosition(
            fixture.controller.splitView.bounds.width - 310,
            ofDividerAt: 2
        )
        layout(fixture)

        fixture.controller.splitViewDidResizeSubviews(
            Notification(name: NSSplitView.didResizeSubviewsNotification, object: fixture.controller.splitView)
        )

        try await Task.sleep(for: .milliseconds(450))

        let persistedSidebarWidth = fixture.widthDefaults.object(forKey: sidebarKey) as? Double
        let persistedDirectoryWidth = fixture.widthDefaults.object(forKey: directoryKey) as? Double
        let persistedInspectorWidth = fixture.widthDefaults.object(forKey: inspectorKey) as? Double
        let expectedSidebarWidth = MainWindowColumnWidth.clampedStorageValue(
            fixture.lists.view.bounds.width,
            range: MainWindowColumnWidth.sidebarRange
        )
        let expectedDirectoryWidth = MainWindowColumnWidth.clampedStorageValue(
            fixture.directory.view.bounds.width,
            range: MainWindowColumnWidth.directoryRange
        )
        let expectedInspectorWidth = MainWindowColumnWidth.clampedStorageValue(
            fixture.inspector.view.bounds.width,
            range: MainWindowColumnWidth.inspectorRange
        )

        #expect(persistedSidebarWidth != nil)
        #expect(persistedDirectoryWidth != nil)
        #expect(persistedInspectorWidth != nil)
        #expect(abs((persistedSidebarWidth ?? 0) - (expectedSidebarWidth ?? 0)) < 1)
        #expect(abs((persistedDirectoryWidth ?? 0) - (expectedDirectoryWidth ?? 0)) < 1)
        #expect(abs((persistedInspectorWidth ?? 0) - (expectedInspectorWidth ?? 0)) < 1)

        #expect((UserDefaults.standard.object(forKey: sidebarKey) as? Double) == standardSidebarBefore)
        #expect((UserDefaults.standard.object(forKey: directoryKey) as? Double) == standardDirectoryBefore)
        #expect((UserDefaults.standard.object(forKey: inspectorKey) as? Double) == standardInspectorBefore)
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
        initialDirectoryWidth: CGFloat = 320,
        initialInspectorWidth: CGFloat = 320,
        readerAccessoryController: NSSplitViewItemAccessoryViewController? = nil,
        inspectorAccessoryController: NSSplitViewItemAccessoryViewController? = nil
    ) -> WorkspaceFixture {
        let lists = makePaneController()
        let directory = makePaneController()
        let reader = makePaneController()
        let inspector = makePaneController()

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
            inspectorController: inspector,
            readerAccessoryController: readerAccessoryController,
            inspectorAccessoryController: inspectorAccessoryController,
            initialListsWidth: initialListsWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            initialInspectorWidth: initialInspectorWidth,
            widthDefaults: widthDefaults
        )
        return WorkspaceFixture(
            controller: controller,
            size: NSSize(width: width, height: 800),
            lists: lists,
            directory: directory,
            reader: reader,
            inspector: inspector,
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

    private func waitForNativeCondition(
        timeout: TimeInterval,
        condition: () -> Bool
    ) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while ProcessInfo.processInfo.systemUptime < deadline {
            if condition() { return true }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
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

    private static let everyAuxiliaryVisibilityCombination = [
        WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: true, inspectorVisible: true),
        WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: true, inspectorVisible: false),
        WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: false, inspectorVisible: true),
        WorkspaceNavigationPaneVisibility(listsVisible: true, directoryVisible: false, inspectorVisible: false),
        WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: true, inspectorVisible: true),
        WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: true, inspectorVisible: false),
        WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: false, inspectorVisible: true),
        WorkspaceNavigationPaneVisibility(listsVisible: false, directoryVisible: false, inspectorVisible: false)
    ]
}

@MainActor
private struct WorkspaceFixture {
    let controller: AppKitWorkspaceNavigationController
    let size: NSSize
    let lists: NSViewController
    let directory: NSViewController
    let reader: NSViewController
    let inspector: NSViewController
    let widthDefaults: UserDefaults
    let defaultsSuiteName: String

    func tearDown() {
        controller.view.removeFromSuperview()
        widthDefaults.removePersistentDomain(forName: defaultsSuiteName)
    }
}

@MainActor
private final class InspectorActionRecorderResponder: NSResponder {
    private(set) var invocationCount = 0

    @objc func toggleInspector(_ sender: Any?) {
        invocationCount += 1
    }
}
