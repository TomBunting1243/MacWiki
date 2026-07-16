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

        #expect(shell.contains("AppKitWorkspaceNavigationSplitView("))
        #expect(!shell.contains("NavigationSplitView(columnVisibility:"))
        #expect(bridge.contains("NSViewControllerRepresentable"))
        #expect(bridge.contains("final class AppKitWorkspaceNavigationController: NSSplitViewController"))
        #expect(bridge.contains("NSSplitViewItem(sidebarWithViewController:"))
        #expect(bridge.contains("NSSplitViewItem(contentListWithViewController:"))
        #expect(bridge.contains("NSSplitViewItem(inspectorWithViewController:"))
        #expect(bridge.contains("inspectorItem.allowsFullHeightLayout = true"))
        #expect(bridge.contains("inspectorItem.canCollapseFromWindowResize = false"))
        #expect(shell.contains("inspectorVisible: $appState.inspectorVisible"))
        #expect(shell.contains("inspector: workspaceEnvironment("))
        #expect(!shell.contains(".inspector(isPresented:"))
        #expect(!shell.contains(".inspectorColumnWidth("))
        #expect(!shell.contains(".persistedColumnWidth("))
        #expect(!shell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(shell.contains(".toolbar {"))
    }

    @Test func readerTabsAndReaderStayInsideOneStableHostedPane() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let bridge = try source("Sources/MacWiki/Views/Shared/AppKitWorkspaceNavigationSplitView.swift")
        let detail = try #require(shell.range(of: "reader: workspaceEnvironment("))
        let inspector = try #require(shell.range(of: "inspector: workspaceEnvironment("))
        let detailSource = String(shell[detail.lowerBound..<inspector.lowerBound])
        let tabs = try #require(detailSource.range(of: "TabBarView("))
        let reader = try #require(detailSource.range(of: "ReaderColumnView()"))

        #expect(tabs.lowerBound < reader.lowerBound)
        #expect(detailSource.contains("VStack(spacing: 0)"))
        #expect(bridge.contains("readerController = NSHostingController("))
        #expect(bridge.contains("readerController.sizingOptions = []"))
        #expect(!bridge.contains("readerController.rootView ="))
    }

    @Test func mainAndArticleWindowsKeepTheirDistinctInspectorPolicies() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let articleWindow = try source("Sources/MacWiki/Views/Shared/ArticleWindowRootView.swift")
        let policy = try source("Sources/MacWiki/Views/Shared/FixedWindowToolbarPolicy.swift")

        #expect(!shell.contains(".inspector(isPresented:"))
        #expect(shell.contains("FixedWindowToolbarPolicy()"))
        #expect(articleWindow.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(articleWindow.contains(".inspectorColumnWidth("))
        #expect(articleWindow.contains("FixedWindowToolbarPolicy()"))
        #expect(policy.contains("NSToolbarItem.Identifier.toggleInspector"))
        #expect(policy.contains("NSToolbarItem.Identifier.inspectorTrackingSeparator"))
        let toggleIndex = try #require(policy.range(of: "toolbar.insertItem(withItemIdentifier: toggle"))
        let separatorIndex = try #require(policy.range(of: "withItemIdentifier: separator"))
        #expect(toggleIndex.lowerBound < separatorIndex.lowerBound)
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
