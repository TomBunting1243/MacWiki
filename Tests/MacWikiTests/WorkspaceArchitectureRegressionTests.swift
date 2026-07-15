import Foundation
import Testing

@Suite
struct WorkspaceArchitectureRegressionTests {
    @Test func hostedPanesUseAStableSceneScopedOpenWindowHandler() throws {
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
        #expect(!shell.contains("forwardedOpenWindowAction"))
        #expect(!handler.contains("@Entry var forwardedOpenWindowAction"))
    }

    @Test func hostedPaneInvalidationIsScopedByPane() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let split = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")

        #expect(shell.contains("sidebarRevision: workspaceAppearanceRevision"))
        #expect(shell.contains("directoryRevision: directoryContentRevision"))
        #expect(shell.contains("readerRevision: readerPresentationRevision"))
        #expect(shell.contains("inspectorRevision: workspaceAppearanceRevision"))
        #expect(split.contains("lastSidebarRevision != sidebarRevision"))
        #expect(split.contains("lastDirectoryRevision != directoryRevision"))
        #expect(split.contains("lastReaderRevision != readerRevision"))
        #expect(split.contains("lastInspectorRevision != inspectorRevision"))
        #expect(split.contains("sidebarBox.content = sidebar"))
        #expect(split.contains("directoryBox.content = directory"))
        #expect(split.contains("readerBox.content = reader"))
        #expect(split.contains("inspectorBox.content = inspector"))
        #expect(!split.contains("contentRevision"))
    }

    @Test func nativeCollapseFeedbackPublishesThroughStableBindingsAfterLayout() throws {
        let shell = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let split = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")
        let controller = try source("Sources/MacWiki/Views/Shared/WorkspaceSplitViewController.swift")

        #expect(shell.contains("sidebarVisible: $appState.listsSidebarVisible"))
        #expect(shell.contains("directoryVisible: $appState.directoryColumnVisible"))
        #expect(shell.contains("inspectorVisible: $appState.inspectorVisible"))
        #expect(split.contains("await Task.yield()"))
        #expect(split.contains("receiveNativeVisibility"))
        #expect(controller.contains("reportUserDrivenVisibilityIfNeeded()"))
        #expect(controller.contains("guard !isApplyingRequestedVisibility else { return }"))
        #expect(controller.contains("onPaneVisibilityChange?(visibility)"))
        #expect(controller.contains("setReaderTopAccessoryViewControllers"))
        #expect(controller.contains("readerItem.topAlignedAccessoryViewControllers = controllers"))
        #expect(split.contains("lastRequestedVisibility != visibility"))
    }

    @Test func nativeWorkspaceAcceptsTheFullWindowProposal() throws {
        let split = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")

        #expect(split.contains("func sizeThatFits("))
        #expect(split.contains("let width = proposal.width"))
        #expect(split.contains("let height = proposal.height"))
        #expect(split.contains("return CGSize(width: width, height: height)"))
        #expect(split.contains("setContentHuggingPriority(.defaultLow, for: .horizontal)"))
    }

    @Test func paneVisibilityDefersOutsideRepresentableUpdatesAndCannotBeCancelledByContentWork() throws {
        let split = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")
        let updateStart = try #require(split.range(of: "func updateWorkspace("))
        let updateSource = String(split[updateStart.lowerBound...])
        let visibilityTask = try #require(updateSource.range(of: "paneVisibilityUpdate = Task"))
        let visibilityYield = try #require(updateSource.range(of: "await Task.yield()"))
        let visibilityApply = try #require(updateSource.range(of: "controller.setPaneVisibility("))
        let deferredContentUpdate = try #require(updateSource.range(of: "hostedContentUpdate = Task"))

        #expect(visibilityTask.lowerBound < visibilityYield.lowerBound)
        #expect(visibilityYield.lowerBound < visibilityApply.lowerBound)
        #expect(visibilityApply.lowerBound < deferredContentUpdate.lowerBound)
        #expect(updateSource.contains("paneVisibilityUpdate?.cancel()"))
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
