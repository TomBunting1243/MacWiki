import AppKit
import Testing

@testable import MacWiki

@Suite(.serialized)
@MainActor
struct NativeWorkspaceSplitViewTests {
    @Test func usesNativeSemanticItemsForAllFourPanes() {
        let fixture = makeFixture(width: 1_700)

        #expect(fixture.controller.splitViewItems.count == 4)
        #expect(fixture.controller.splitViewItems[0].behavior == .sidebar)
        #expect(fixture.controller.splitViewItems[1].behavior == .contentList)
        #expect(fixture.controller.splitViewItems[2].behavior == .default)
        #expect(fixture.controller.splitViewItems[3].behavior == .inspector)
        #expect(fixture.controller.splitViewItems[0].allowsFullHeightLayout)
        #expect(fixture.controller.splitViewItems[3].allowsFullHeightLayout)
        #expect(fixture.controller.splitViewItems[0].canCollapse)
        #expect(fixture.controller.splitViewItems[1].canCollapse)
        #expect(!fixture.controller.splitViewItems[2].canCollapse)
        #expect(fixture.controller.splitViewItems[3].canCollapse)
    }

    @Test func restoresAllAuxiliaryPaneWidthsInPoints() {
        let fixture = makeFixture(width: 1_700)
        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))

        #expect(abs(fixture.sidebar.view.bounds.width - 220) < 0.5)
        #expect(abs(fixture.directory.view.bounds.width - 320) < 0.5)
        #expect(abs(fixture.inspector.view.bounds.width - 340) < 0.5)
        #expect(fixture.reader.view.bounds.width >= MainWindowLayout.minimumReaderWidth)
    }

    @Test func readerRemainsPresentWhenEveryAuxiliaryPaneCollapses() {
        let fixture = makeFixture(width: 1_400)
        fixture.controller.setPaneVisibility(
            sidebarVisible: false,
            directoryVisible: false,
            inspectorVisible: false,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_400, height: 800))

        #expect(fixture.controller.splitViewItems[0].isCollapsed)
        #expect(fixture.controller.splitViewItems[1].isCollapsed)
        #expect(!fixture.controller.splitViewItems[2].isCollapsed)
        #expect(fixture.controller.splitViewItems[3].isCollapsed)
        #expect(fixture.reader.view.bounds.width > MainWindowLayout.minimumReaderWidth)
    }

    @Test func adoptsValidAdaptiveWidthsWhenStoredWidthsCannotFit() {
        let fixture = makeFixture(width: 1_300)
        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_300, height: 800))
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture.controller, size: NSSize(width: 1_300, height: 800))
        #expect(
            abs(fixture.sidebar.view.bounds.width - 220) >= 0.5
                || abs(fixture.directory.view.bounds.width - 320) >= 0.5
                || abs(fixture.inspector.view.bounds.width - 340) >= 0.5
        )
        #expect(fixture.reader.view.bounds.width > 0)

        let adaptiveWidths = [
            fixture.sidebar.view.bounds.width,
            fixture.directory.view.bounds.width,
            fixture.inspector.view.bounds.width
        ]

        fixture.window.setContentSize(NSSize(width: 1_700, height: 800))
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))

        #expect(abs(fixture.sidebar.view.bounds.width - adaptiveWidths[0]) < 0.5)
        #expect(abs(fixture.directory.view.bounds.width - adaptiveWidths[1]) < 0.5)
        #expect(abs(fixture.inspector.view.bounds.width - adaptiveWidths[2]) < 0.5)
        #expect(fixture.reader.view.bounds.width >= MainWindowLayout.minimumReaderWidth)
    }

    @Test func restoringPanesDoesNotResizeAnAlreadyNarrowWindow() {
        let fixture = makeFixture(width: 1_700)
        fixture.window.setContentSize(NSSize(width: 900, height: 800))
        fixture.controller.setPaneVisibility(
            sidebarVisible: false,
            directoryVisible: false,
            inspectorVisible: false,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 900, height: 800))
        let originalWindowWidth = fixture.window.frame.width

        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 900, height: 800))

        #expect(fixture.window.frame.width == originalWindowWidth)
        #expect(!fixture.controller.splitViewItems[0].isCollapsed)
        #expect(!fixture.controller.splitViewItems[1].isCollapsed)
        #expect(!fixture.controller.splitViewItems[3].isCollapsed)
        #expect(fixture.reader.view.bounds.width > 0)
    }

    @Test func reportsNativeUserCollapseAcrossAllAuxiliaryPanes() {
        let fixture = makeFixture(width: 1_700)
        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))

        var reportedVisibility: WorkspacePaneVisibility?
        fixture.controller.onPaneVisibilityChange = { reportedVisibility = $0 }
        fixture.controller.splitViewItems[0].isCollapsed = true
        fixture.controller.splitViewItems[1].isCollapsed = true
        fixture.controller.splitViewItems[3].isCollapsed = true
        fixture.controller.splitViewDidResizeSubviews(
            Notification(
                name: NSSplitView.didResizeSubviewsNotification,
                object: fixture.controller.splitView
            )
        )

        #expect(reportedVisibility == WorkspacePaneVisibility(
            sidebarVisible: false,
            directoryVisible: false,
            inspectorVisible: false
        ))
        #expect(!fixture.controller.splitViewItems[2].isCollapsed)
    }

    @Test func persistsUserResizedAuxiliaryWidthsAfterDebounce() async throws {
        let defaults = isolatedDefaults()
        defaults.set(220.0, forKey: AppStorageKey.MainWindow.sidebarWidth)
        defaults.set(320.0, forKey: AppStorageKey.MainWindow.directoryWidth)
        defaults.set(340.0, forKey: AppStorageKey.MainWindow.inspectorWidth)
        let fixture = makeFixture(width: 1_700, defaults: defaults)
        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()

        fixture.controller.splitView.setPosition(240, ofDividerAt: 0)
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))
        let directoryLeadingEdge = fixture.directory.view.convert(
            .zero,
            to: fixture.controller.splitView
        ).x
        fixture.controller.splitView.setPosition(
            directoryLeadingEdge + 360,
            ofDividerAt: 1
        )
        fixture.controller.splitView.setPosition(
            fixture.controller.splitView.bounds.width - 380,
            ofDividerAt: 2
        )
        layout(fixture.controller, size: NSSize(width: 1_700, height: 800))
        fixture.controller.splitViewDidResizeSubviews(
            Notification(
                name: NSSplitView.didResizeSubviewsNotification,
                object: fixture.controller.splitView
            )
        )

        try await Task.sleep(for: .milliseconds(200))
        #expect(defaults.double(forKey: AppStorageKey.MainWindow.sidebarWidth) == 220)
        #expect(defaults.double(forKey: AppStorageKey.MainWindow.directoryWidth) == 320)
        #expect(defaults.double(forKey: AppStorageKey.MainWindow.inspectorWidth) == 340)

        try await waitUntil(timeout: .seconds(2)) {
            abs(defaults.double(forKey: AppStorageKey.MainWindow.sidebarWidth) - 240) < 0.5
                && abs(defaults.double(forKey: AppStorageKey.MainWindow.directoryWidth) - 360) < 0.5
                && abs(defaults.double(forKey: AppStorageKey.MainWindow.inspectorWidth) - 380) < 0.5
        }
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.sidebarWidth) - 240) < 0.5)
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.directoryWidth) - 360) < 0.5)
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.inspectorWidth) - 380) < 0.5)
    }

    @Test func persistsDividerChangesAfterAdaptingStoredWidthsToNarrowWindow() async throws {
        let defaults = isolatedDefaults()
        defaults.set(260.0, forKey: AppStorageKey.MainWindow.sidebarWidth)
        defaults.set(420.0, forKey: AppStorageKey.MainWindow.directoryWidth)
        defaults.set(460.0, forKey: AppStorageKey.MainWindow.inspectorWidth)
        let fixture = makeFixture(
            width: 1_300,
            defaults: defaults,
            initialSidebarWidth: 260,
            initialDirectoryWidth: 420,
            initialInspectorWidth: 460
        )
        fixture.controller.setPaneVisibility(
            sidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true,
            animated: false
        )
        layout(fixture.controller, size: NSSize(width: 1_300, height: 800))
        fixture.controller.restoreInitialVisibleWidthsIfFeasible()

        fixture.controller.splitView.setPosition(210, ofDividerAt: 0)
        layout(fixture.controller, size: NSSize(width: 1_300, height: 800))
        let directoryLeadingEdge = fixture.directory.view.convert(
            .zero,
            to: fixture.controller.splitView
        ).x
        fixture.controller.splitView.setPosition(
            directoryLeadingEdge + 300,
            ofDividerAt: 1
        )
        fixture.controller.splitView.setPosition(
            fixture.controller.splitView.bounds.width - 310,
            ofDividerAt: 2
        )
        layout(fixture.controller, size: NSSize(width: 1_300, height: 800))
        fixture.controller.splitViewDidResizeSubviews(
            Notification(
                name: NSSplitView.didResizeSubviewsNotification,
                object: fixture.controller.splitView
            )
        )

        try await waitUntil(timeout: .seconds(2)) {
            abs(defaults.double(forKey: AppStorageKey.MainWindow.sidebarWidth) - 210) < 0.5
                && abs(defaults.double(forKey: AppStorageKey.MainWindow.directoryWidth) - 300) < 0.5
                && abs(defaults.double(forKey: AppStorageKey.MainWindow.inspectorWidth) - 310) < 0.5
        }
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.sidebarWidth) - 210) < 0.5)
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.directoryWidth) - 300) < 0.5)
        #expect(abs(defaults.double(forKey: AppStorageKey.MainWindow.inspectorWidth) - 310) < 0.5)
    }

    private func makeFixture(
        width: CGFloat,
        defaults: UserDefaults? = nil,
        initialSidebarWidth: CGFloat = 220,
        initialDirectoryWidth: CGFloat = 320,
        initialInspectorWidth: CGFloat = 340
    ) -> WorkspaceFixture {
        let sidebar = NSViewController()
        let directory = NSViewController()
        let reader = NSViewController()
        let inspector = NSViewController()
        let controller = WorkspaceSplitViewController(
            sidebarController: sidebar,
            directoryController: directory,
            readerController: reader,
            inspectorController: inspector,
            initialSidebarWidth: initialSidebarWidth,
            initialDirectoryWidth: initialDirectoryWidth,
            initialInspectorWidth: initialInspectorWidth,
            widthDefaults: defaults ?? isolatedDefaults()
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 800),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        return WorkspaceFixture(
            controller: controller,
            window: window,
            sidebar: sidebar,
            directory: directory,
            reader: reader,
            inspector: inspector
        )
    }

    private func layout(_ controller: WorkspaceSplitViewController, size: NSSize) {
        controller.view.frame = NSRect(origin: .zero, size: size)
        controller.splitView.frame = controller.view.bounds
        controller.splitView.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "NativeWorkspaceSplitViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func waitUntil(
        timeout: Duration,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

@MainActor
private struct WorkspaceFixture {
    let controller: WorkspaceSplitViewController
    let window: NSWindow
    let sidebar: NSViewController
    let directory: NSViewController
    let reader: NSViewController
    let inspector: NSViewController
}
