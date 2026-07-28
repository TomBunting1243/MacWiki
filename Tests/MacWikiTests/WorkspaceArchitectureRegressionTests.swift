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
