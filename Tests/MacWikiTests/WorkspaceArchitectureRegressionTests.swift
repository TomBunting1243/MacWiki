import Foundation
import Testing

@Suite
struct WorkspaceArchitectureRegressionTests {
    @Test func workspaceUsesAStableSceneScopedOpenWindowHandler() throws {
        let handler = try source("Sources/MacWiki/Views/Shared/WorkspaceOpenWindowHandler.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let contextMenu = try source("Sources/MacWiki/Views/Components/ArticleContextMenuContent.swift")

        #expect(handler.contains("final class WorkspaceOpenWindowHandler"))
        #expect(handler.contains("private var action: OpenWindowAction?"))
        #expect(handler.contains("@Entry var workspaceOpenWindowHandler: WorkspaceOpenWindowHandler?"))
        #expect(shell.contains("@State private var openWindowHandler = WorkspaceOpenWindowHandler()"))
        #expect(shell.contains("openWindowHandler.update(action: openWindow)"))
        #expect(shell.contains(".environment(\\.workspaceOpenWindowHandler, openWindowHandler)"))
        #expect(reader.contains("workspaceOpenWindowHandler?.open(article) != true"))
        #expect(contextMenu.contains("workspaceOpenWindowHandler?.open(windowArticle) != true"))
    }

    @Test func mainWorkspaceUsesOneFourPaneAppKitSplitWithAFullHeightInspector() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        let toolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let toolbarItemFactory = try source(
            "Sources/MacWiki/Views/Shared/WorkspaceToolbarItemFactory.swift"
        )

        #expect(shell.contains("AppKitWorkspaceNavigationSplitView("))
        #expect(!shell.contains("NavigationSplitView(columnVisibility:"))
        #expect(bridge.contains("NSViewControllerRepresentable"))
        #expect(bridge.contains("final class AppKitWorkspaceNavigationController: NSSplitViewController"))
        #expect(bridge.contains("NSSplitViewItem(sidebarWithViewController:"))
        #expect(bridge.contains("NSSplitViewItem(contentListWithViewController:"))
        #expect(bridge.contains("NSSplitViewItem(inspectorWithViewController:"))
        #expect(bridge.contains("NSSplitViewItemAccessoryViewController"))
        #expect(bridge.contains("readerItem.addTopAlignedAccessoryViewController("))
        #expect(!bridge.contains("inspectorItem.addTopAlignedAccessoryViewController("))
        #expect(bridge.contains("listsItem.allowsFullHeightLayout = true"))
        #expect(bridge.contains("inspectorItem.allowsFullHeightLayout = true"))
        #expect(!bridge.contains("automaticallyAppliesContentInsets = false"))
        #expect(bridge.contains("final class WorkspaceInspectorHostingController"))
        #expect(bridge.contains("surface.material = .sidebar"))
        #expect(bridge.contains("surface.blendingMode = .behindWindow"))
        #expect(bridge.contains("inspectorItem.canCollapseFromWindowResize = false"))
        #expect(shell.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(shell.contains("inspectorVisible: $appState.inspectorVisible"))
        #expect(shell.contains("inspector: workspaceEnvironment("))
        #expect(!shell.contains(".inspector(isPresented:"))
        #expect(!shell.contains(".inspectorColumnWidth("))
        #expect(!shell.contains(".persistedColumnWidth("))
        #expect(!shell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!shell.contains(".toolbar {"))
        #expect(shell.contains("toolbarConfiguration: WorkspaceToolbarConfiguration("))
        #expect(bridge.contains("toolbarController = WorkspaceToolbarController("))
        #expect(bridge.contains("toolbarController?.update(configuration: configuration)"))
        #expect(toolbar.contains("let toolbar = NSToolbar(identifier: WorkspaceToolbarLayout.toolbarIdentifier)"))
        #expect(toolbarItemFactory.contains("NSTrackingSeparatorToolbarItem("))
        #expect(toolbar.contains("dividerIndex: 0"))
        #expect(toolbar.contains("dividerIndex: 1"))
        #expect(toolbar.contains("dividerIndex: 2"))
        #expect(!toolbar.contains("NSHostingView"))
    }

    @Test func readerTabsUseTheirPlaneAccessoryAndInspectorModesUseNativeWindowToolbar() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        let toolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let inspectorToolbarItem = try source(
            "Sources/MacWiki/Views/Shared/WorkspaceInspectorToolbarItemController.swift"
        )
        let inspectorPanel = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let webView = try source("Sources/MacWiki/Views/Components/WebView.swift")
        let detail = try #require(shell.range(of: "reader: workspaceEnvironment("))
        let inspector = try #require(shell.range(of: "inspector: workspaceEnvironment("))
        let readerAccessory = try #require(shell.range(of: "readerAccessory: workspaceEnvironment("))
        let detailSource = String(shell[detail.lowerBound..<inspector.lowerBound])
        let readerAccessorySource = String(shell[readerAccessory.lowerBound...])

        #expect(detailSource.contains("ReaderColumnView()"))
        #expect(!detailSource.contains("TabBarView("))
        #expect(readerAccessorySource.contains("TabBarView("))
        #expect(!readerAccessorySource.contains("InspectorHeaderBar("))
        #expect(shell.contains("InspectorColumnView(includesHeader: false)"))
        #expect(!shell.contains("InspectorModeAccessoryHost"))
        #expect(!shell.contains("inspectorAccessory:"))
        #expect(!bridge.contains("inspectorAccessoryController"))
        #expect(toolbar.contains("inspectorModesController.makeItem(identifier:"))
        #expect(inspectorToolbarItem.contains("NSToolbarItemGroup("))
        #expect(inspectorToolbarItem.contains("item.role = .tabs"))
        #expect(inspectorToolbarItem.contains("action: #selector(selectInspectorMode(_:))"))
        // Standalone article windows still use the Inspector panel's embedded header.
        #expect(inspectorPanel.contains("InspectorHeaderBar(selection: $appState.inspectorMode)"))
        #expect(inspectorPanel.contains("if includesHeader"))
        #expect(bridge.contains("readerController = NSHostingController("))
        #expect(bridge.contains("readerController.sizingOptions = []"))
        #expect(!bridge.contains("readerController.rootView ="))
        #expect(!reader.contains("inspectorMode: appState.inspectorMode"))
        #expect(!webView.contains("inspectorMode"))
        #expect(!webView.contains("inspectorVisible"))
    }

    @Test func mainAndArticleWindowsKeepTheirDistinctInspectorPolicies() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let app = try source("Sources/MacWiki/App/MacWikiApp.swift")
        let workspaceToolbar = try source("Sources/MacWiki/Views/Shared/WorkspaceToolbarController.swift")
        let articleWindow = try source("Sources/MacWiki/Views/Shared/ArticleWindowRootView.swift")
        let policy = try source("Sources/MacWiki/Views/Shared/FixedWindowToolbarPolicy.swift")

        #expect(!shell.contains(".inspector(isPresented:"))
        #expect(!shell.contains(".toolbar {"))
        #expect(!shell.contains("FixedWindowToolbarPolicy()"))
        #expect(shell.contains("toolbarConfiguration: WorkspaceToolbarConfiguration("))
        // Only the standalone Article scene retains SwiftUI's toolbar style.
        #expect(
            app.components(separatedBy: ".windowToolbarStyle(.unified(showsTitle: false))").count - 1 == 1
        )
        #expect(workspaceToolbar.contains("guard window.toolbar == nil else"))
        #expect(workspaceToolbar.contains("window.toolbar = toolbar"))
        #expect(workspaceToolbar.contains("let stillOwnsWindowChrome = stillOwnsToolbar || window?.toolbar == nil"))
        #expect(workspaceToolbar.contains("if stillOwnsWindowChrome"))
        #expect(workspaceToolbar.contains("window.toolbar = nil"))
        #expect(articleWindow.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(articleWindow.contains(".inspectorColumnWidth("))
        #expect(articleWindow.contains(".toolbar {"))
        #expect(articleWindow.contains("ArticleWindowReaderToolbar("))
        #expect(articleWindow.contains("FixedWindowToolbarPolicy()"))
        #expect(!policy.contains("insertItem"))
        #expect(!policy.contains("removeItem"))
        #expect(!policy.contains("inspectorTrackingSeparator"))
        #expect(!policy.contains("WorkspaceInspectorResponder"))
    }

    @Test func navigationVisibilityUsesTwoIndependentStoredBindings() throws {
        let appState = try source("Sources/MacWiki/App/AppState.swift")
        let navigation = try source("Sources/MacWiki/App/AppState+NavigationTabs.swift")
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(appState.contains("var listsSidebarVisible = true"))
        #expect(appState.contains("var directoryColumnVisible = true"))
        #expect(!appState.contains("NavigationSplitViewVisibility"))
        #expect(!appState.contains("WorkspaceNavigationColumns"))
        #expect(shell.contains("listsVisible: $appState.listsSidebarVisible"))
        #expect(shell.contains("directoryVisible: $appState.directoryColumnVisible"))
        #expect(navigation.contains("guard !isWikiHopNavigationLocked else { return }"))
        #expect(navigation.contains("listsSidebarVisible.toggle()"))
        #expect(navigation.contains("directoryColumnVisible.toggle()"))
    }

    @Test func obsoleteSplitAndWindowMinimumBridgesAreGone() {
        for path in [
            "Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift",
            "Sources/MacWiki/Views/Shared/WorkspaceSplitViewController.swift",
            "Sources/MacWiki/Views/Shared/WindowContentMinimumSizeBridge.swift",
            "Sources/MacWiki/Views/Shared/ReaderTopChromeView.swift",
            "Sources/MacWiki/Views/Shared/NativeReaderToolbarButton.swift"
        ] {
            #expect(!FileManager.default.fileExists(atPath: repositoryRoot.appending(path: path).path))
        }
    }

    @Test func windowMinimumIsStableAcrossPaneVisibilityChanges() throws {
        let content = try source("Sources/MacWiki/Views/ContentView.swift")

        #expect(content.contains("minWidth: MainWindowLayout.minimumWindowWidth"))
        #expect(!content.contains("WindowContentMinimumSizeBridge"))
        #expect(!content.contains("minimumContentWidth("))
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
