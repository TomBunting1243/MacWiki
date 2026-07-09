import SwiftUI
import SwiftData
import AppKit
import os

private let appBootstrapLogger = Logger(subsystem: "com.macwiki", category: "app-bootstrap")

private struct MacWikiLaunchIssue: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

@MainActor
final class MacWikiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        AppIconLoader.applyIfAvailable()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            MacWikiRuntime.shared.presentMainWindowIfNeeded()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MacWikiRuntime.shared.presentMainWindowIfNeeded()
            return false
        }
        return true
    }
}

@MainActor
private final class MacWikiRuntime {
    static let shared = MacWikiRuntime()

    private var appState: AppState?
    private var modelContainer: ModelContainer?
    private var launchIssue: MacWikiLaunchIssue?
    private var hasPresentedFallbackLaunchIssue = false
    private var fallbackMainWindow: NSWindow?

    func configure(
        appState: AppState,
        modelContainer: ModelContainer,
        launchIssue: MacWikiLaunchIssue?
    ) {
        self.appState = appState
        self.modelContainer = modelContainer
        self.launchIssue = launchIssue
    }

    func presentMainWindowIfNeeded() {
        if let existingWindow = NSApp.windows.first(where: { window in
            !(window is NSPanel) && window.canBecomeKey
        }) {
            appBootstrapLogger.notice("Ordering existing main window to front")
            existingWindow.deminiaturize(nil)
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if hasOnScreenWindow() {
                return
            }
        }

        if let fallbackMainWindow {
            appBootstrapLogger.notice("Reopening fallback main window")
            fallbackMainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let appState, let modelContainer else {
            appBootstrapLogger.error("Cannot present fallback main window before runtime configuration")
            return
        }
        appBootstrapLogger.notice("Presenting fallback main window")
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(
            contentRect: visibleFrame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacWiki"
        window.isReleasedWhenClosed = false
        window.setFrame(visibleFrame, display: false)
        window.contentView = NSHostingView(
            rootView: ContentView()
                .focusedSceneValue(\.macWikiCommandAppState, appState)
                .toolbar(removing: .title)
                .toolbar(removing: .sidebarToggle)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .configuredMacWikiWindowChrome()
                .environment(appState)
                .modelContainer(modelContainer)
        )
        fallbackMainWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        presentFallbackLaunchIssueIfNeeded(for: window)
    }

    private func hasOnScreenWindow() -> Bool {
        let processID = Int(ProcessInfo.processInfo.processIdentifier)
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windowInfo.contains { info in
            guard
                info[kCGWindowOwnerPID as String] as? Int == processID,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0
            else {
                return false
            }
            return true
        }
    }

    private func presentFallbackLaunchIssueIfNeeded(for window: NSWindow) {
        guard let launchIssue, !hasPresentedFallbackLaunchIssue else { return }
        hasPresentedFallbackLaunchIssue = true

        let alert = NSAlert()
        alert.messageText = launchIssue.title
        alert.informativeText = launchIssue.message
        alert.addButton(withTitle: "Continue")
        alert.beginSheetModal(for: window)
    }
}

/// MacWiki - A native macOS Wikipedia client
/// 
/// Entry point for the application. Configures the main window
/// and initializes global state.
@main
struct MacWikiApp: App {
    private struct ModelContainerBootstrap {
        let modelContainer: ModelContainer
        let launchIssue: MacWikiLaunchIssue?
    }

    @NSApplicationDelegateAdaptor(MacWikiAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var appState: AppState
    @State private var launchIssue: MacWikiLaunchIssue?
    @State private var hasPresentedLaunchIssue = false
    private let bootstrap: ModelContainerBootstrap

    init() {
        Self.configureGlobalURLCache()
        Self.sanitizePersistedWindowAndSplitViewState()
        let bootstrap = Self.makeModelContainerBootstrap()
        let appState = AppState()
        self.bootstrap = bootstrap
        _appState = State(initialValue: appState)
        _launchIssue = State(initialValue: nil)
        MacWikiRuntime.shared.configure(
            appState: appState,
            modelContainer: bootstrap.modelContainer,
            launchIssue: bootstrap.launchIssue
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            MacWikiRuntime.shared.presentMainWindowIfNeeded()
        }
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
                    launchIssue: MacWikiLaunchIssue(
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
        let directory = MacWikiURLCacheStorage.systemDirectoryURL()

        if directory == nil {
            appBootstrapLogger.error(
                "Unable to create MacWiki URL cache directory; using the system default cache location"
            )
        }

        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: directory
        )
    }

    private static func sanitizePersistedWindowAndSplitViewState() {
        let defaults = UserDefaults.standard
        let entries = defaults.dictionaryRepresentation()
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let shellLayoutMigrationKey = "mainWindow.shellLayoutVersion"
        let currentShellLayoutVersion = 12

        // Search is now a single sidebar-resident surface. Drop the retired overlay preference.
        defaults.removeObject(forKey: AppStorageKey.Search.presentationMode)

        if defaults.integer(forKey: shellLayoutMigrationKey) < currentShellLayoutVersion {
            defaults.removeObject(forKey: AppStorageKey.MainWindow.sidebarWidth)
            defaults.removeObject(forKey: AppStorageKey.MainWindow.directoryWidth)
            defaults.removeObject(forKey: AppStorageKey.MainWindow.inspectorWidth)
            defaults.removeObject(forKey: AppStorageKey.ArticleWindow.inspectorWidth)
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v2")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v3")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v4")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v5")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v6")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v7")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v8")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v9")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v10")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v11")
            defaults.removeObject(forKey: "NSToolbar Configuration main-window-toolbar-v12")
            defaults.set(currentShellLayoutVersion, forKey: shellLayoutMigrationKey)
        }

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

        sanitizePersistedSplitWidth(defaults, key: AppStorageKey.MainWindow.sidebarWidth, minimum: 176, maximum: 260)
        sanitizePersistedSplitWidth(defaults, key: AppStorageKey.MainWindow.directoryWidth, minimum: 260, maximum: 420)
        sanitizePersistedSplitWidth(defaults, key: AppStorageKey.MainWindow.inspectorWidth, minimum: 260, maximum: 460)
        sanitizePersistedSplitWidth(defaults, key: AppStorageKey.ArticleWindow.inspectorWidth, minimum: 260, maximum: 460)
    }

    private static func sanitizePersistedSplitWidth(
        _ defaults: UserDefaults,
        key: String,
        minimum: Double,
        maximum: Double
    ) {
        guard let storedValue = defaults.object(forKey: key) as? Double else { return }
        guard storedValue.isFinite else {
            defaults.removeObject(forKey: key)
            return
        }

        if storedValue < minimum || storedValue > maximum {
            defaults.removeObject(forKey: key)
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
        Window("MacWiki", id: "main") {
            ContentView()
                .focusedSceneValue(\.macWikiCommandAppState, appState)
                .toolbar(removing: .title)
                .toolbar(removing: .sidebarToggle)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .configuredMacWikiWindowChrome()
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
                .environment(appState)
        }
        .modelContainer(bootstrap.modelContainer)
        .restorationBehavior(.disabled)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(
            width: Self.launchWindowSize.width,
            height: Self.launchWindowSize.height
        )
        .defaultLaunchBehavior(.presented)
        .commands {
            MacWikiCommands(
                fallbackAppState: appState,
                showAboutPanel: showAboutPanel,
                adjustReaderFontSize: { adjustReaderFontSize(by: $0) },
                resetReaderFontSize: resetReaderFontSize
            )
        }

        WindowGroup("Article", for: Article.self) { $article in
            if let article = article {
                ArticleWindowRootView(initialArticle: article)
            } else {
                ContentUnavailableView(
                    "No Article Selected",
                    systemImage: "doc.text",
                    description: Text("Open an article from a context menu to create a dedicated article window.")
                )
            }
        }
        .modelContainer(bootstrap.modelContainer)
        .restorationBehavior(.disabled)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(
            width: Self.launchWindowSize.width,
            height: Self.launchWindowSize.height
        )
        .defaultLaunchBehavior(.suppressed)
        
        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(bootstrap.modelContainer)
    }

}
