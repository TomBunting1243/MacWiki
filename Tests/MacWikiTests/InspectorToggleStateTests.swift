import Testing

@testable import MacWiki

@MainActor
struct InspectorToggleStateTests {
    @Test func repeatedInspectorTogglesRemainDeterministic() {
        let appState = AppState()
        openSampleArticle(in: appState)

        #expect(appState.inspectorVisible == true)

        for step in 1...20 {
            appState.toggleInspectorVisibility()
            let expectedVisible = (step % 2 == 0)
            #expect(appState.inspectorVisible == expectedVisible)
        }
    }

    private func openSampleArticle(in appState: AppState) {
        appState.openArticle(Article(id: "inspector-toggle-sample", title: "Inspector Toggle Sample"))
    }
}
