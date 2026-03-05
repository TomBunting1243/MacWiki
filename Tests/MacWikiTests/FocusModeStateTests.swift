import Testing

@testable import MacWiki

@MainActor
struct FocusModeStateTests {
    @Test func enableAndDisableFocusRestoresCapturedColumnVisibility() {
        let appState = AppState()
        openSampleArticle(in: appState)
        appState.sidebarVisible = true
        appState.inspectorVisible = false

        appState.setFocusModeEnabled(true)

        #expect(appState.isFocusModeEnabled == true)
        #expect(appState.sidebarVisible == false)
        #expect(appState.inspectorVisible == false)

        appState.setFocusModeEnabled(false)

        #expect(appState.isFocusModeEnabled == false)
        #expect(appState.sidebarVisible == true)
        #expect(appState.inspectorVisible == false)
    }

    @Test func focusRestoreHonorsAsymmetricCapturedState() {
        let appState = AppState()
        openSampleArticle(in: appState)
        appState.sidebarVisible = false
        appState.inspectorVisible = true

        appState.setFocusModeEnabled(true)
        appState.setFocusModeEnabled(false)

        #expect(appState.sidebarVisible == false)
        #expect(appState.inspectorVisible == true)
    }

    @Test func enablingFocusTwiceIsIdempotent() {
        let appState = AppState()
        openSampleArticle(in: appState)
        appState.sidebarVisible = true
        appState.inspectorVisible = true

        appState.setFocusModeEnabled(true)
        appState.sidebarVisible = true
        appState.inspectorVisible = true
        appState.setFocusModeEnabled(true)
        appState.setFocusModeEnabled(false)

        #expect(appState.sidebarVisible == true)
        #expect(appState.inspectorVisible == true)
    }

    @Test func factoryResetClearsFocusModeState() {
        let appState = AppState()
        openSampleArticle(in: appState)
        appState.sidebarVisible = false
        appState.inspectorVisible = true
        appState.setFocusModeEnabled(true)

        appState.resetForFactoryDefaults()

        #expect(appState.isFocusModeEnabled == false)
        #expect(appState.sidebarVisible == true)
        #expect(appState.inspectorVisible == true)
    }

    @Test func focusModeRequiresActiveArticle() {
        let appState = AppState()
        appState.createNewTab()
        appState.setFocusModeEnabled(true)
        #expect(appState.isFocusModeEnabled == false)
    }

    @Test func switchingToNewTabDisablesFocusAndRestoresColumns() {
        let appState = AppState()
        openSampleArticle(in: appState)
        appState.sidebarVisible = false
        appState.inspectorVisible = true
        appState.setFocusModeEnabled(true)

        appState.createNewTab()

        #expect(appState.currentArticle == nil)
        #expect(appState.isFocusModeEnabled == false)
        #expect(appState.sidebarVisible == false)
        #expect(appState.inspectorVisible == true)
    }

    private func openSampleArticle(in appState: AppState) {
        appState.openArticle(Article(id: "focus-mode-sample", title: "Focus Mode Sample"))
    }
}
