import SwiftUI

private struct MacWikiCommandAppStateKey: FocusedValueKey {
    typealias Value = AppState
}

extension FocusedValues {
    var macWikiCommandAppState: AppState? {
        get { self[MacWikiCommandAppStateKey.self] }
        set { self[MacWikiCommandAppStateKey.self] = newValue }
    }
}

@MainActor
struct MacWikiCommands: Commands {
    @FocusedValue(\.macWikiCommandAppState) private var focusedAppState

    let fallbackAppState: AppState
    let showAboutPanel: () -> Void
    let adjustReaderFontSize: (Double) -> Void
    let resetReaderFontSize: () -> Void

    private var appState: AppState {
        focusedAppState ?? fallbackAppState
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacWiki") {
                showAboutPanel()
            }
        }

        SidebarCommands()
        ToolbarCommands()

        CommandGroup(after: .textEditing) {
            Button("Search Wikipedia") {
                appState.startSearch(context: .navigation)
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(appState.isWikiHopNavigationLocked)

            Button("Find in Page") {
                appState.presentFindOnPage()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(appState.currentArticle == nil)
        }

        CommandGroup(after: .newItem) {
            Button("New Reading List") {
                appState.requestNewReadingList()
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])

            Button("New Folder") {
                appState.requestNewFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("New Tab") {
                appState.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(appState.isWikiHopNavigationLocked)

            Button("Close Tab") {
                appState.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(appState.activeTabId == nil || appState.isWikiHopNavigationLocked)

            Button("Reopen Closed Tab") {
                appState.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(appState.recentlyClosedTabs.isEmpty || appState.isWikiHopNavigationLocked)

            Divider()

            Button("Save Article...") {
                appState.presentOptionClickSavePromptForCurrentArticle()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(appState.currentArticle == nil)
        }

        CommandGroup(after: .pasteboard) {
            Button("Add to List...") {
                appState.showAddToList = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(appState.activeTabId == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Next Tab") {
                appState.nextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(appState.openTabs.isEmpty || appState.isWikiHopNavigationLocked)

            Button("Next Tab") {
                appState.nextTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(appState.openTabs.isEmpty || appState.isWikiHopNavigationLocked)

            Button("Previous Tab") {
                appState.previousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(appState.openTabs.isEmpty || appState.isWikiHopNavigationLocked)

            Button("Previous Tab") {
                appState.previousTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(appState.openTabs.isEmpty || appState.isWikiHopNavigationLocked)

            Divider()

            Button("Toggle Inspector") {
                appState.toggleInspectorVisibility()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(!appState.inspectorPresentationAvailable)
        }

        CommandGroup(after: .windowSize) {
            Button("Increase Reader Font Size") {
                adjustReaderFontSize(1)
            }
            .keyboardShortcut("=", modifiers: .command)

            Button("Decrease Reader Font Size") {
                adjustReaderFontSize(-1)
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Reset Reader Font Size") {
                resetReaderFontSize()
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
