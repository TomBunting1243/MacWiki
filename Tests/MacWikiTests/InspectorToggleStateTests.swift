import Testing

@testable import MacWiki

@MainActor
struct InspectorToggleStateTests {
    @Test func repeatedInspectorTogglesRemainDeterministic() {
        let appState = AppState(persistenceMode: .ephemeral)
        openSampleArticle(in: appState)
        appState.inspectorPresentationAvailable = true

        #expect(appState.inspectorVisible == true)
        #expect(appState.inspectorPresented == true)

        for step in 1...20 {
            appState.toggleInspectorVisibility()
            let expectedVisible = (step % 2 == 0)
            #expect(appState.inspectorVisible == expectedVisible)
            #expect(appState.inspectorPresented == expectedVisible)
        }
    }

    @Test func responsiveSuppressionPreservesInspectorPreference() {
        let appState = AppState(persistenceMode: .ephemeral)
        openSampleArticle(in: appState)

        #expect(appState.inspectorVisible == true)
        #expect(appState.inspectorPresented == false)

        appState.inspectorPresentationAvailable = true
        #expect(appState.inspectorPresented == true)

        appState.inspectorPresentationAvailable = false
        appState.inspectorPresented = false
        #expect(appState.inspectorVisible == true)

        appState.inspectorPresentationAvailable = true
        #expect(appState.inspectorPresented == true)
    }

    private func openSampleArticle(in appState: AppState) {
        appState.openArticle(Article(id: "inspector-toggle-sample", title: "Inspector Toggle Sample"))
    }
}
