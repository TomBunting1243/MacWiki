import SwiftUI
import Testing

@testable import MacWiki

@Suite @MainActor
struct WorkspaceOpenWindowHandlerTests {
    @Test func openWithoutAnActionFallsBackWithoutClaimingSuccess() {
        let handler = WorkspaceOpenWindowHandler()
        let article = Article(id: "fallback", title: "Fallback")

        #expect(handler.open(article) == false)
    }

    @Test func openInvokesTheActionExactlyOnceWithTheArticleWindowValue() {
        let action = RecordingOpenWindowAction()
        let handler = WorkspaceOpenWindowHandler(actionAdapter: action)
        let article = Article(
            id: "ada-lovelace",
            title: "Ada Lovelace",
            description: "English mathematician"
        )

        #expect(handler.open(article))
        #expect(action.openedArticles == [article])
    }

    @Test func updatingTheActionReplacesThePreviousDestination() {
        let initialAction = RecordingOpenWindowAction()
        let replacementAction = RecordingOpenWindowAction()
        let handler = WorkspaceOpenWindowHandler(actionAdapter: initialAction)
        let firstArticle = Article(id: "first", title: "First")
        let secondArticle = Article(id: "second", title: "Second")

        #expect(handler.open(firstArticle))
        handler.update(actionAdapter: replacementAction)
        #expect(handler.open(secondArticle))

        #expect(initialAction.openedArticles == [firstArticle])
        #expect(replacementAction.openedArticles == [secondArticle])
    }

    @Test func environmentRetainsTheSceneScopedHandlerWhileItsActionUpdates() {
        let handler = WorkspaceOpenWindowHandler()
        let action = RecordingOpenWindowAction()
        let article = Article(id: "scene", title: "Scene")
        var environment = EnvironmentValues()
        environment.workspaceOpenWindowHandler = handler

        handler.update(actionAdapter: action)

        #expect(environment.workspaceOpenWindowHandler === handler)
        #expect(environment.workspaceOpenWindowHandler?.open(article) == true)
        #expect(action.openedArticles == [article])
    }
}

@MainActor
private final class RecordingOpenWindowAction: WorkspaceOpenWindowActionAdapter {
    private(set) var openedArticles: [Article] = []

    func openWindow(with article: Article) {
        openedArticles.append(article)
    }
}
