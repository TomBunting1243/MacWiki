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

    @Test func mainWorkspaceUsesPlatformOwnedNavigationAndInspectorContainers() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(shell.contains("NavigationSplitView(columnVisibility: $appState.navigationSplitViewVisibility)"))
        #expect(shell.contains("} content: {"))
        #expect(shell.contains("} detail: {"))
        #expect(shell.contains(".navigationSplitViewStyle(.balanced)"))
        #expect(shell.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(shell.components(separatedBy: ".navigationSplitViewColumnWidth(").count - 1 == 2)
        #expect(shell.components(separatedBy: ".persistedColumnWidth(").count - 1 == 3)
        #expect(shell.contains(".inspectorColumnWidth("))
        #expect(!shell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(shell.contains(".toolbar(id: MainWindowReaderToolbarIdentifier.configuration)"))
    }

    @Test func readerTabsRemainInsideTheDetailColumn() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let detail = try #require(shell.range(of: "} detail: {"))
        let inspector = try #require(shell.range(of: ".inspector(isPresented:"))
        let detailSource = String(shell[detail.lowerBound..<inspector.lowerBound])
        let tabs = try #require(detailSource.range(of: "TabBarView("))
        let reader = try #require(detailSource.range(of: "ReaderColumnView()"))

        #expect(tabs.lowerBound < reader.lowerBound)
        #expect(detailSource.contains("VStack(spacing: 0)"))
    }

    @Test func visibilityIsOneInvariantStateBoundByKeyPath() throws {
        let appState = try source("Sources/MacWiki/App/AppState.swift")
        let navigation = try source("Sources/MacWiki/App/AppState+NavigationTabs.swift")

        #expect(appState.contains("var navigationSplitViewVisibility: NavigationSplitViewVisibility = .all"))
        #expect(appState.contains("var workspaceNavigationColumns: WorkspaceNavigationColumns {"))
        #expect(appState.contains("var listsSidebarVisible: Bool"))
        #expect(appState.contains("var directoryColumnVisible: Bool"))
        #expect(appState.contains("SDK 27 intentionally considers `.automatic` equal to"))
        #expect(appState.contains("if isWikiHopNavigationLocked,"))
        #expect(appState.contains("navigationSplitViewVisibility = .detailOnly"))
        #expect(navigation.contains("guard !isWikiHopNavigationLocked else { return }"))
        #expect(!navigation.contains("listsSidebarVisible.toggle()"))
        #expect(!navigation.contains("directoryColumnVisible.toggle()"))
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
