import SwiftUI
import SwiftData
import AppKit
import os

private let appBootstrapLogger = Logger(subsystem: "com.macwiki", category: "app-bootstrap")

@MainActor
final class MacWikiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppIconLoader.applyIfAvailable()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// MacWiki - A native macOS Wikipedia client
/// 
/// Entry point for the application. Configures the main window
/// and initializes global state.
@main
struct MacWikiApp: App {
    private struct LaunchIssue: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private struct ModelContainerBootstrap {
        let modelContainer: ModelContainer
        let launchIssue: LaunchIssue?
    }

    @NSApplicationDelegateAdaptor(MacWikiAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState
    @State private var launchIssue: LaunchIssue?
    @State private var hasPresentedLaunchIssue = false
    private let bootstrap: ModelContainerBootstrap

    init() {
        Self.configureGlobalURLCache()
        Self.sanitizePersistedWindowAndSplitViewState()
        let bootstrap = Self.makeModelContainerBootstrap()
        self.bootstrap = bootstrap
        _appState = State(initialValue: AppState())
        _launchIssue = State(initialValue: nil)
    }

    private static var modelSchema: Schema {
        Schema([
            ReadingList.self,
            SavedArticle.self,
            Area.self,
            Label.self,
            Tag.self,
            Highlight.self,
            ArticleNote.self,
            ArticleState.self
        ])
    }

    private static func makeModelContainerBootstrap() -> ModelContainerBootstrap {
        do {
            return ModelContainerBootstrap(
                modelContainer: try ModelContainer(for: modelSchema),
                launchIssue: nil
            )
        } catch {
            appBootstrapLogger.error("Failed to initialize persistent SwiftData store: \(error.localizedDescription, privacy: .public)")
            // Corrupted or incompatible on-disk stores can crash app launch.
            // Fall back to an in-memory container so the app stays bootable,
            // but surface the degraded mode because changes in this session
            // will not persist.
            do {
                let config = ModelConfiguration(schema: modelSchema, isStoredInMemoryOnly: true)
                return ModelContainerBootstrap(
                    modelContainer: try ModelContainer(for: modelSchema, configurations: [config]),
                    launchIssue: LaunchIssue(
                        title: "Storage Recovery Mode",
                        message: "MacWiki could not open its saved library data, so this launch is using a temporary in-memory session. Your saved lists, highlights, and notes were not loaded, and changes made now will not persist after you quit."
                    )
                )
            } catch {
                fatalError("Failed to initialize SwiftData model container: \(error.localizedDescription)")
            }
        }
    }

    private static func configureGlobalURLCache() {
        // Discover/search surfaces are thumbnail-heavy and rely on `AsyncImage`, which uses `URLCache`.
        // A larger shared cache avoids repeated downloads when opening new tabs during research bursts.
        let memoryCapacity = 48 * 1024 * 1024
        let diskCapacity = 240 * 1024 * 1024
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: "MacWikiURLCache"
        )
    }

    private static func sanitizePersistedWindowAndSplitViewState() {
        let defaults = UserDefaults.standard
        let entries = defaults.dictionaryRepresentation()
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)

        for (key, value) in entries {
            if key.hasPrefix("NSWindow Frame SwiftUI."),
               key.contains("AppWindow") {
                if WindowFrameSanitizer.shouldDiscardAutosavedWindowFrame(value, availableFrames: visibleFrames) {
                    defaults.removeObject(forKey: key)
                }
                continue
            }

            if key.hasPrefix("NSSplitView Subview Frames SwiftUI."),
               key.contains("SidebarNavigationSplitView") {
                // Column widths are already persisted via AppStorage in view state.
                // Removing split autosave avoids stale frame inflation across launches.
                defaults.removeObject(forKey: key)
            }
        }
    }

    private static var launchWindowSize: CGSize {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return CGSize(width: visibleFrame.width, height: visibleFrame.height)
    }

    private func adjustReaderFontSize(by delta: Double) {
        let defaults = UserDefaults.standard
        let key = ReaderAppearanceStorageKey.fontSize
        let current = defaults.object(forKey: key) as? Double ?? ReaderAppearance.default.fontSize
        let updated = min(
            max(current + delta, ReaderAppearance.fontSizeRange.lowerBound),
            ReaderAppearance.fontSizeRange.upperBound
        )
        defaults.set(updated, forKey: key)
    }

    private func resetReaderFontSize() {
        UserDefaults.standard.set(ReaderAppearance.default.fontSize, forKey: ReaderAppearanceStorageKey.fontSize)
    }

    private func showAboutPanel() {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let linkAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "A native macOS Wikipedia client.\n\n",
            attributes: bodyAttributes
        ))
        credits.append(NSAttributedString(string: "Project: ", attributes: bodyAttributes))
        credits.append(Self.linkString(
            "GitHub Repository",
            url: "https://github.com/tombunting/MacWiki",
            baseAttributes: linkAttributes
        ))
        credits.append(NSAttributedString(string: "\nLicense: ", attributes: bodyAttributes))
        credits.append(Self.linkString(
            "Apache-2.0",
            url: "https://github.com/tombunting/MacWiki/blob/main/LICENSE",
            baseAttributes: linkAttributes
        ))
        credits.append(NSAttributedString(string: "\nTrademark: ", attributes: bodyAttributes))
        credits.append(Self.linkString(
            "MacWiki Trademark",
            url: "https://github.com/tombunting/MacWiki/blob/main/TRADEMARK.md",
            baseAttributes: linkAttributes
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationVersion: "Version \(shortVersion) (\(buildNumber))",
            .credits: credits
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func linkString(
        _ title: String,
        url: String,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        guard let parsedURL = URL(string: url) else {
            return NSAttributedString(string: title, attributes: baseAttributes)
        }

        var attributes = baseAttributes
        attributes[.link] = parsedURL
        return NSAttributedString(string: title, attributes: attributes)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .alert(item: $launchIssue) { issue in
                    Alert(
                        title: Text(issue.title),
                        message: Text(issue.message),
                        dismissButton: .default(Text("Continue"))
                    )
                }
                .task {
                    guard !hasPresentedLaunchIssue else { return }
                    hasPresentedLaunchIssue = true
                    if let issue = bootstrap.launchIssue {
                        launchIssue = issue
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase != .active {
                        appState.flushSaveNow()
                    }
                }
        }
        .modelContainer(bootstrap.modelContainer)
        .restorationBehavior(.disabled)
        .windowStyle(.automatic)
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(
            width: Self.launchWindowSize.width,
            height: Self.launchWindowSize.height
        )
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MacWiki") {
                    showAboutPanel()
                }
            }

            SidebarCommands()
            ToolbarCommands()

            // Search commands
            CommandGroup(after: .textEditing) {
                Button("Search Wikipedia") {
                    appState.startSearch(context: .navigation)
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.isWikiHopNavigationLocked || appState.isFocusModeEnabled)

                Button("Find in Page") {
                    guard !appState.isFocusModeEnabled else { return }
                    appState.showFindOnPage = true
                    appState.findOnPageMatchFound = nil
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(appState.currentArticle == nil || appState.isFocusModeEnabled)
            }
            
            // Tab commands
            CommandGroup(after: .newItem) {
                Button("New Reading List") {
                    NotificationCenter.default.post(name: .macWikiRequestNewReadingList, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])

                Button("New Folder") {
                    NotificationCenter.default.post(name: .macWikiRequestNewFolder, object: nil)
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
            }
            
            // Article commands
            CommandGroup(replacing: .saveItem) {
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
            
            // Navigation commands
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
                .disabled(appState.isFocusModeEnabled)

                Button(appState.isFocusModeEnabled ? "Exit Focus Mode" : "Enter Focus Mode") {
                    appState.toggleFocusMode()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])
                .disabled(appState.currentArticle == nil || appState.isWikiHopNavigationLocked)
            }

            // Reader typography shortcuts
            CommandGroup(after: .windowSize) {
                Button("Increase Reader Font Size") {
                    adjustReaderFontSize(by: 1)
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Decrease Reader Font Size") {
                    adjustReaderFontSize(by: -1)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Reset Reader Font Size") {
                    resetReaderFontSize()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(bootstrap.modelContainer)
    }

}
