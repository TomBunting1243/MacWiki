import Testing

@testable import MacWiki

@MainActor
struct OptionClickSavePromptTests {
    @Test func presentOptionClickSavePromptStoresRequestedArticle() {
        let appState = AppState()
        let article = Article(id: "Swift_(programming_language)", title: "Swift (programming language)")

        appState.presentOptionClickSavePrompt(for: article)

        #expect(appState.optionClickSaveRequest?.article == article)
    }

    @Test func dismissOptionClickSavePromptClearsPendingRequest() {
        let appState = AppState()
        let article = Article(id: "Swift_(programming_language)", title: "Swift (programming language)")
        appState.presentOptionClickSavePrompt(for: article)

        appState.dismissOptionClickSavePrompt()

        #expect(appState.optionClickSaveRequest == nil)
    }
}
