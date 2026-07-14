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

        CommandGroup(after: .newItem) {
            if supports(.libraryOrganization) {
                Button("New Reading List") {
                    appState.requestNewReadingList()
                }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])

                Button("New Folder") {
                    appState.requestNewFolder()
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()
            }

            if supports(.tabs) {
                Button("New Tab") {
                    appState.createNewTab()
                }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(appState.isWikiHopNavigationLocked)

                Button("Close Tab") {
                    appState.closeActiveTab()
                }
                .keyboardShortcut("w", modifiers: .command)
                .disabled(
                    appState.activeTabId == nil
                        || appState.isWikiHopNavigationLocked
                )

                Button("Reopen Closed Tab") {
                    appState.reopenLastClosedTab()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(
                    appState.recentlyClosedTabs.isEmpty
                        || appState.isWikiHopNavigationLocked
                )

                Divider()
            }

            if supports(.reader) {
                Button("Save Article...") {
                    appState.presentOptionClickSavePromptForCurrentArticle()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(
                    appState.currentArticle == nil
                        || appState.isWikiHopNavigationLocked
                )
            }
        }

        CommandGroup(after: .pasteboard) {
            if supports(.reader) {
                Button("Add to List...") {
                    appState.showAddToList = true
                }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(
                    appState.currentArticle == nil
                        || appState.isWikiHopNavigationLocked
                )
            }
        }

        CommandGroup(after: .toolbar) {
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

        CommandMenu("Article") {
            Button("Back") {
                appState.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(
                !supports(.reader)
                    || appState.currentTab?.canGoBack != true
                    || appState.isWikiHopNavigationLocked
            )

            Button("Forward") {
                appState.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(
                !supports(.reader)
                    || appState.currentTab?.canGoForward != true
                    || appState.isWikiHopNavigationLocked
            )

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
            Button("Next Tab") {
                appState.nextTab()
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(
                !supports(.tabs)
                    || appState.openTabs.isEmpty
                    || appState.isWikiHopNavigationLocked
            )

            Button("Next Tab") {
                appState.nextTab()
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            .disabled(
                !supports(.tabs)
                    || appState.openTabs.isEmpty
                    || appState.isWikiHopNavigationLocked
            )

            Button("Previous Tab") {
                appState.previousTab()
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(
                !supports(.tabs)
                    || appState.openTabs.isEmpty
                    || appState.isWikiHopNavigationLocked
            )

            Button("Previous Tab") {
                appState.previousTab()
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            .disabled(
                !supports(.tabs)
                    || appState.openTabs.isEmpty
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
