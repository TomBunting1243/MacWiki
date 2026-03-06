import SwiftUI

struct MainWindowToolbar: ToolbarContent {
    @Environment(AppState.self) private var appState

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button(
                appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns",
                systemImage: "sidebar.leading",
                action: toggleSidebar
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked)
            .help(appState.sidebarVisible ? "Hide Navigation Columns" : "Show Navigation Columns")

            Button(
                "Search Wikipedia",
                systemImage: "magnifyingglass",
                action: startSearch
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked || appState.isFocusModeEnabled)
            .help("Search Wikipedia")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Button(
                "New Tab",
                systemImage: "plus",
                action: appState.createNewTab
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isWikiHopNavigationLocked)
            .help("New Tab")

            Button(
                appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode",
                systemImage: appState.isFocusModeEnabled ? "viewfinder.circle.fill" : "viewfinder.circle",
                action: toggleFocusMode
            )
            .labelStyle(.iconOnly)
            .disabled(appState.currentArticle == nil || appState.isWikiHopNavigationLocked)
            .help(appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode")

            Button(
                appState.inspectorVisible ? "Hide Inspector" : "Show Inspector",
                systemImage: "sidebar.trailing",
                action: toggleInspector
            )
            .labelStyle(.iconOnly)
            .disabled(appState.isFocusModeEnabled)
            .help(appState.inspectorVisible ? "Hide Inspector" : "Show Inspector")
        }
    }

    private func toggleSidebar() {
        guard !appState.isWikiHopNavigationLocked else { return }
        withAnimation(ColumnMotion.sidebarVisibility) {
            appState.sidebarVisible.toggle()
        }
    }

    private func startSearch() {
        appState.startSearch(context: .navigation)
    }

    private func toggleFocusMode() {
        guard appState.currentArticle != nil else { return }
        appState.toggleFocusMode()
    }

    private func toggleInspector() {
        guard !appState.isFocusModeEnabled else { return }
        withAnimation(ColumnMotion.inspectorVisibility) {
            appState.toggleInspectorVisibility()
        }
    }
}
