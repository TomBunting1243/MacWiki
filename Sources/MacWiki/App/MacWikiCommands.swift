import AppKit
import SwiftData
import SwiftUI

struct MacWikiCommandCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let workspaceNavigation = Self(rawValue: 1 << 0)
    static let libraryOrganization = Self(rawValue: 1 << 1)
    static let tabs = Self(rawValue: 1 << 2)
    static let reader = Self(rawValue: 1 << 3)
    static let inspector = Self(rawValue: 1 << 4)

    static let mainWorkspace: Self = [
        .workspaceNavigation,
        .libraryOrganization,
        .tabs,
        .reader,
        .inspector
    ]
    static let articleWindow: Self = [.reader, .inspector]
}

enum MacWikiCloseCommandPolicy {
    static func usesNativeWindowClose(
        for capabilities: MacWikiCommandCapabilities
    ) -> Bool {
        !capabilities.contains(.tabs)
    }
}

extension FocusedValues {
    @Entry var macWikiCommandAppState: AppState?
    @Entry var macWikiInspectorCommandsAvailable: Bool?
    @Entry var macWikiCommandCapabilities: MacWikiCommandCapabilities?
    @Entry var macWikiCommandModelContext: ModelContext?
}

@MainActor
struct MacWikiCommands: Commands {
    @FocusedValue(\.macWikiCommandAppState) private var focusedAppState
    @FocusedValue(\.macWikiInspectorCommandsAvailable) private var inspectorCommandsAvailable
    @FocusedValue(\.macWikiCommandCapabilities) private var focusedCommandCapabilities
    @FocusedValue(\.macWikiCommandModelContext) private var commandModelContext

    let fallbackAppState: AppState
    let showAboutPanel: () -> Void
    let adjustReaderFontSize: (Double) -> Void
    let resetReaderFontSize: () -> Void

    private var appState: AppState {
        focusedAppState ?? fallbackAppState
    }

    private var commandCapabilities: MacWikiCommandCapabilities {
        focusedCommandCapabilities ?? []
    }

    private func supports(_ capability: MacWikiCommandCapabilities) -> Bool {
        commandCapabilities.contains(capability)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About MacWiki") {
                showAboutPanel()
            }
        }

        // SwiftUI's standard save-item group owns Command-W for Close Window.
        // The tabbed workspace instead assigns that shortcut to Close Tab in
        // the Tabs menu, so keep exactly one shortcut owner for each scene.
        CommandGroup(replacing: .saveItem) {
            if MacWikiCloseCommandPolicy.usesNativeWindowClose(
                for: commandCapabilities
            ) {
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("w", modifiers: .command)
            }
        }

        SidebarCommands()
        ToolbarCommands()

        CommandGroup(after: .textEditing) {
            if supports(.workspaceNavigation) {
                Button("Search Wikipedia") {
                    appState.startSearch(context: .navigation)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.isWikiHopNavigationLocked)
            }

            if supports(.reader) {
                Button("Find in Page") {
                    appState.presentFindOnPage()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(
                    appState.currentArticle == nil
                        || appState.isWikiHopNavigationLocked
                )
            }
        }

        CommandGroup(after: .toolbar) {
            if supports(.workspaceNavigation) {
                Button(appState.listsSidebarVisible ? "Hide Lists" : "Show Lists") {
                    appState.toggleListsSidebarVisibility()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(appState.isWikiHopNavigationLocked)

                Button(appState.directoryColumnVisible ? "Hide List Contents" : "Show List Contents") {
                    appState.toggleDirectoryColumnVisibility()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                .disabled(appState.isWikiHopNavigationLocked)

                Divider()
            }

            Button("Toggle Inspector") {
                appState.toggleInspectorVisibility()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(
                inspectorCommandsAvailable != true
                    || !supports(.inspector)
            )

            Divider()

            Button("Increase Reader Font Size") {
                adjustReaderFontSize(1)
            }
            .keyboardShortcut("=", modifiers: .command)
            .disabled(!readerActionIsAvailable)

            Button("Decrease Reader Font Size") {
                adjustReaderFontSize(-1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!readerActionIsAvailable)

            Button("Reset Reader Font Size") {
                resetReaderFontSize()
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!readerActionIsAvailable)
        }

        CommandMenu("Library") {
            Button("New Reading List") {
                appState.requestNewReadingList()
            }
            .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            .disabled(!supports(.libraryOrganization))

            Button("New Folder") {
                appState.requestNewFolder()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(!supports(.libraryOrganization))
        }

        CommandMenu("Article") {
            Button("Back") {
                appState.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(
                !supports(.reader)
                    || !appState.canGoBack
                    || appState.isWikiHopNavigationLocked
            )

            Button("Forward") {
                appState.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(
                !supports(.reader)
                    || !appState.canGoForward
                    || appState.isWikiHopNavigationLocked
            )

            Divider()

            Button("Save Article…") {
                appState.presentOptionClickSavePromptForCurrentArticle()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!readerActionIsAvailable)

            Button("Add to List…") {
                appState.showAddToList = true
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(!readerActionIsAvailable)

            Divider()

            Button(appState.currentArticle?.isRead == true ? "Mark as Unread" : "Mark as Read") {
                toggleCurrentArticleReadState()
            }
            .disabled(
                !supports(.reader)
                    || appState.currentArticle == nil
                    || commandModelContext == nil
                    || appState.isWikiHopNavigationLocked
            )

            Button("Reader Style…") {
                appState.requestReaderStylePresentation()
            }
            .disabled(
                !supports(.reader)
                    || appState.currentArticle == nil
                    || appState.isWikiHopNavigationLocked
            )

            Button("Page Views…") {
                appState.requestReaderPageViewsPresentation()
            }
            .disabled(
                !supports(.reader)
                    || appState.currentArticle == nil
                    || appState.isWikiHopNavigationLocked
            )

            Button("Open in Browser") {
                if let article = appState.currentArticle {
                    NSWorkspace.shared.open(article.url)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])
            .disabled(
                !supports(.reader)
                    || appState.currentArticle == nil
                    || appState.isWikiHopNavigationLocked
            )

            Button("Share…") {
                if let article = appState.currentArticle {
                    ReaderSharePresenter.shared.show(article.url)
                }
            }
            .disabled(
                !supports(.reader)
                    || appState.currentArticle == nil
                    || appState.isWikiHopNavigationLocked
            )
        }

        CommandMenu("Tabs") {
            Button("New Tab") {
                appState.createNewTab()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(
                !supports(.tabs)
                    || appState.isWikiHopNavigationLocked
            )

            Button("Close Tab") {
                appState.closeActiveTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(
                !supports(.tabs)
                    || appState.activeTabId == nil
                    || appState.isWikiHopNavigationLocked
            )

            Button("Reopen Closed Tab") {
                appState.reopenLastClosedTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(
                !supports(.tabs)
                    || appState.recentlyClosedTabs.isEmpty
                    || appState.isWikiHopNavigationLocked
            )

            Divider()

            Button("Next Tab") {
                appState.nextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(
                !supports(.tabs)
                    || !appState.hasOpenTabs
                    || appState.isWikiHopNavigationLocked
            )

            Button("Previous Tab") {
                appState.previousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(
                !supports(.tabs)
                    || !appState.hasOpenTabs
                    || appState.isWikiHopNavigationLocked
            )

        }
    }

    private var readerActionIsAvailable: Bool {
        supports(.reader)
            && appState.currentArticle != nil
            && !appState.isWikiHopNavigationLocked
    }

    private func toggleCurrentArticleReadState() {
        guard let article = appState.currentArticle,
              let commandModelContext,
              !appState.isWikiHopNavigationLocked else {
            return
        }
        _ = ReadStateSync.applyReadState(
            !article.isRead,
            for: article,
            in: commandModelContext,
            appState: appState
        )
    }
}
