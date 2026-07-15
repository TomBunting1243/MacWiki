import Foundation
import Testing

@testable import MacWiki

@MainActor
struct NativeDesignRegressionTests {
    @Test func sidebarSearchInheritsTheTransparentSidebarSurface() throws {
        let source = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")

        #expect(!source.contains("textBackgroundColor"))
        #expect(!source.contains("windowBackgroundColor"))
        #expect(source.contains(".safeAreaPadding(.top)"))
    }

    @Test func sidebarSelectionIsOwnedByTheNativeSidebarList() throws {
        let sidebar = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")
        let chrome = try source("Sources/MacWiki/Views/Sidebar/SidebarRowChrome.swift")

        #expect(sidebar.contains("List(selection: $sidebarSelectionSet)"))
        #expect(sidebar.contains(".listStyle(.sidebar)"))
        #expect(!chrome.contains("selectedFill"))
        #expect(!chrome.contains("hoverFill"))
        #expect(!chrome.contains("RoundedRectangle(cornerRadius: SidebarRowMetrics.rowCornerRadius"))
        #expect(!chrome.contains(".onHover"))
    }

    @Test func activeWindowVisualsUseTheModernSwiftUIEnvironmentValue() throws {
        let paths = [
            "Sources/MacWiki/Views/Components/FindOnPageBarView.swift",
            "Sources/MacWiki/Views/Components/ReaderTabItemView.swift",
            "Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift",
            "Sources/MacWiki/Views/Sidebar/SidebarDropTargetModifier.swift"
        ]

        for path in paths {
            let source = try source(path)
            #expect(source.contains("@Environment(\\.appearsActive)"))
            #expect(!source.contains("controlActiveState"))
        }
    }

    @Test func settingsUseValueBasedNativeTabs() throws {
        let settingsSource = try source("Sources/MacWiki/Views/Components/SettingsView.swift")
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")

        #expect(settingsSource.components(separatedBy: "            Tab(").count == 6)
        #expect(!settingsSource.contains(".tabItem"))
        #expect(!settingsSource.contains(".tag("))
        #expect(appSource.contains("Settings {\n            SettingsView()"))

        for tab in ["reading", "library", "navigation", "chrome", "advanced"] {
            #expect(settingsSource.contains("value: SettingsTab.\(tab)"))
        }
    }

    @Test func sharedColumnStatesUseNativeUnavailablePresentationAndActions() throws {
        let sharedState = try source("Sources/MacWiki/Views/Shared/ColumnEmptyStateView.swift")
        let searchState = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchStateView.swift")
        let searchContent = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchContentView.swift")

        #expect(sharedState.contains("struct ColumnEmptyStateView<Actions: View>: View"))
        #expect(sharedState.contains("ContentUnavailableView"))
        #expect(sharedState.contains("@ViewBuilder actions: () -> Actions"))
        #expect(sharedState.contains("title: LocalizedStringResource"))
        #expect(sharedState.contains("description: LocalizedStringResource"))
        #expect(!sharedState.contains("VStack(spacing:"))

        #expect(searchState.contains("ColumnEmptyStateView("))
        #expect(searchState.contains("Button(actionTitle, systemImage: \"arrow.clockwise\", action: action)"))
        #expect(searchState.contains(".keyboardShortcut(.defaultAction)"))
        #expect(!searchState.contains(".padding(.top, -10)"))
        #expect(searchContent.contains("message: Text(verbatim: message)"))
    }

    @Test func inspectorEmptyStatesShareTheNativePrimitiveAndTransientStatusIsAnnounced() throws {
        let inspectorModes = try source("Sources/MacWiki/Views/Inspector/InspectorModeViews.swift")
        let inspectorPanel = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")

        #expect(inspectorModes.components(separatedBy: "ColumnEmptyStateView(").count == 3)
        #expect(!inspectorModes.contains("inspectorModeEmptyState"))
        #expect(inspectorModes.contains("let message: LocalizedStringResource"))
        #expect(inspectorModes.contains(".accessibilityLabel(Text(toast.message))"))
        #expect(inspectorModes.contains("NSAccessibility.post("))
        #expect(inspectorModes.contains("element: NSApplication.shared"))
        #expect(inspectorModes.contains("notification: .announcementRequested"))
        #expect(inspectorModes.contains(".announcement: String(localized: message)"))
        #expect(inspectorModes.contains(".priority: priority.rawValue"))
        #expect(inspectorModes.contains("showsSpinner || toast.isSuccess ? .medium : .high"))
        #expect(inspectorPanel.contains("appState.isHighlightRehydrateInProgress"))
        #expect(inspectorPanel.contains("result.success ? \"Rehydrate succeeded\" : \"Rehydrate failed\""))
        #expect(inspectorPanel.contains("VSplitView"))
        #expect(inspectorPanel.contains("List(selection: tableOfContentsSelection)"))
        #expect(inspectorPanel.contains(".listStyle(.plain)"))
        #expect(inspectorPanel.contains(".frame(minHeight: InspectorLayout.contentsMinimumHeight)"))
        #expect(!inspectorPanel.contains("standardTOCTransition"))
        #expect(!inspectorPanel.contains("Form {"))
        #expect(!inspectorPanel.contains("DisclosureGroup(\"Contents\""))
    }

    @Test func readerTabsAndFindBarHonorWindowAndAccessibilityPersonalization() throws {
        let tabBar = try source("Sources/MacWiki/Views/Components/TabBarView.swift")
        let tabItem = try source("Sources/MacWiki/Views/Components/ReaderTabItemView.swift")
        let tabAccessories = try source("Sources/MacWiki/Views/Components/ReaderTabAccessoryCluster.swift")
        let tabContextMenu = try source("Sources/MacWiki/Views/Components/ReaderTabContextMenuContent.swift")
        let findBar = try source("Sources/MacWiki/Views/Components/FindOnPageBarView.swift")

        #expect(tabBar.contains("@Environment(\\.macWikiAccessibilityPersonalization)"))
        #expect(tabBar.contains("ReaderTabAccessoryCluster("))

        #expect(tabAccessories.contains("@Environment(\\.macWikiAccessibilityPersonalization)"))
        #expect(tabAccessories.contains("ControlGroup"))
        #expect(!tabAccessories.contains(".glassEffect("))
        #expect(!tabAccessories.contains(".thinMaterial"))

        #expect(tabItem.contains("@Environment(\\.appearsActive)"))
        #expect(!tabItem.contains("controlActiveState"))
        #expect(tabItem.contains("@Environment(\\.macWikiAccessibilityPersonalization)"))
        #expect(tabItem.contains("accessibilityPersonalization.reduceTransparency"))
        #expect(tabItem.contains("accessibilityPersonalization.colorSchemeContrast == .increased"))
        #expect(tabItem.contains("accessibilityPersonalization.differentiateWithoutColor"))
        #expect(tabItem.contains("Image(systemName: \"highlighter\")"))
        #expect(tabItem.contains("Color(nsColor: .selectedContentBackgroundColor)"))
        #expect(!tabItem.contains(".glassEffect("))
        #expect(tabItem.contains("isKeyWindow && isActive && !isDragged"))
        #expect(tabItem.contains("ReaderTabContextMenuContent("))
        #expect(!tabItem.contains("@Environment(\\.modelContext)"))

        #expect(tabContextMenu.contains("@Environment(\\.modelContext)"))
        #expect(tabContextMenu.contains("DebouncedActionScheduler"))
        #expect(tabContextMenu.contains("flushScheduledModelContextSave()"))

        #expect(findBar.contains("@Environment(\\.appearsActive)"))
        #expect(!findBar.contains("controlActiveState"))
        #expect(findBar.contains("@Environment(\\.macWikiAccessibilityPersonalization)"))
        #expect(findBar.contains(") && !accessibilityPersonalization.reduceTransparency"))
        #expect(findBar.contains("Color(nsColor: accessibilityPersonalization.reduceTransparency ? .controlBackgroundColor : .windowBackgroundColor)"))
        #expect(findBar.contains("isKeyWindow && !accessibilityPersonalization.reduceTransparency"))
        #expect(findBar.contains("increasedContrast ? 1"))
        #expect(findBar.contains(".onChange(of: appState.findOnPageFocusRequestID)"))
    }

    @Test func linkHoverPreviewUsesNativeGlassPolicyAndSolidAccessibilityFallback() throws {
        let source = try source("Sources/MacWiki/Views/Components/WebView/WebViewLinkHoverPreviewPane.swift")

        #expect(source.contains("@Environment(\\.macWikiAccessibilityPersonalization)"))
        #expect(source.contains("MacWikiGlassRuntime.usesNativeGlass("))
        #expect(source.contains(") && !accessibilityPersonalization.reduceTransparency"))
        #expect(source.contains("if accessibilityPersonalization.reduceTransparency"))
        #expect(source.contains("else if #available(macOS 26, *), usesNativeGlass"))
        #expect(source.contains(".glassEffect("))
        #expect(source.contains(".fill(Color(nsColor: .windowBackgroundColor))"))
        #expect(source.contains(".fill(.thinMaterial)"))
        #expect(!source.contains("MacWikiGlassGroup("))
    }

    @Test func readerToolbarsCommandsAndStyleControlsStayNativeReachableAndLockedSafely() throws {
        let toolbar = try source("Sources/MacWiki/Views/Shared/MainWindowReaderToolbar.swift")
        let articleToolbar = try source("Sources/MacWiki/Views/Shared/ArticleWindowReaderToolbar.swift")
        let articleWindow = try source("Sources/MacWiki/Views/Shared/ArticleWindowRootView.swift")
        let toolbarPolicy = try source("Sources/MacWiki/Views/Shared/FixedWindowToolbarPolicy.swift")
        let commands = try source("Sources/MacWiki/App/MacWikiCommands.swift")
        let style = try source("Sources/MacWiki/Views/Components/ReaderStylePopover.swift")

        #expect(toolbar.contains("ToolbarContent"))
        #expect(!toolbar.contains("CustomizableToolbarContent"))
        #expect(toolbar.contains("ControlGroup"))
        #expect(toolbar.contains("ToolbarItem(placement: .navigation)"))
        #expect(toolbar.contains("ToolbarItemGroup(placement: .primaryAction)"))
        #expect(!toolbar.contains("ToolbarSpacer("))
        #expect(toolbar.contains(".disabled(article == nil)"))
        #expect(toolbar.contains("appState.canGoBack"))
        #expect(!toolbar.contains("toggleListsSidebarVisibility"))
        #expect(!toolbar.contains("sidebar.leading"))
        #expect(toolbar.contains("toggleDirectoryColumnVisibility"))
        #expect(toolbar.contains("reader-find-in-page"))
        #expect(articleToolbar.contains("ToolbarContent"))
        #expect(!articleToolbar.contains("CustomizableToolbarContent"))
        #expect(articleToolbar.contains("ToolbarItem(placement: .navigation)"))
        #expect(articleToolbar.contains("ToolbarItemGroup(placement: .primaryAction)"))
        #expect(!articleToolbar.contains("ToolbarSpacer("))
        #expect(toolbarPolicy.contains("NSToolbarItem.Identifier.inspectorTrackingSeparator"))
        #expect(toolbarPolicy.contains("NSToolbarItem.Identifier.toggleInspector"))
        #expect(toolbarPolicy.contains("toolbar.allowsUserCustomization = false"))
        for action in ["Save Article", "Mark as Read", "Find in Page", "Reader Style", "Page Views", "Open in Browser", "Share"] {
            #expect(toolbar.contains(action))
            #expect(articleToolbar.contains(action))
            #expect(commands.contains(action))
        }
        #expect(commands.contains("CommandGroup(after: .toolbar)"))
        #expect(commands.contains("appState.directoryColumnVisible ? \"Hide List Contents\" : \"Show List Contents\""))
        #expect(commands.contains("appState.toggleDirectoryColumnVisibility()"))
        #expect(commands.contains(".keyboardShortcut(\"l\", modifiers: [.command, .option])"))
        #expect(commands.contains("CommandMenu(\"Article\")"))
        #expect(commands.contains("CommandMenu(\"Tabs\")"))
        #expect(commands.components(separatedBy: "Button(\"Next Tab\")").count - 1 == 1)
        #expect(commands.components(separatedBy: "Button(\"Previous Tab\")").count - 1 == 1)
        #expect(commands.contains(".keyboardShortcut(.tab, modifiers: .control)"))
        #expect(commands.contains(".keyboardShortcut(.tab, modifiers: [.control, .shift])"))
        #expect(!commands.contains("CommandGroup(after: .windowSize)"))
        #expect(articleWindow.contains(".onChange(of: appState.readerStylePresentationRequestID)"))
        #expect(articleWindow.contains("showsReaderStylePopover = true"))
        #expect(articleWindow.contains(".onChange(of: appState.readerPageViewsPresentationRequestID)"))
        #expect(articleWindow.contains("showsPageViewsPopover = true"))
        for obsoletePath in [
            "Sources/MacWiki/Views/Shared/ArticleWindowReaderCommandPresenter.swift",
            "Sources/MacWiki/Views/Shared/ReaderToolbarPopoverPresenter.swift"
        ] {
            #expect(!FileManager.default.fileExists(
                atPath: repositoryRoot().appendingPathComponent(obsoletePath).path
            ))
        }
        #expect(style.contains("SwiftUI.Label(\"Apply Preset\", systemImage:"))
        #expect(style.contains(".accessibilityLabel(\"Apply Reader Preset\")"))
        #expect(style.contains(".accessibilityLabel(Text(title))"))
        #expect(style.contains(".accessibilityValue(Text(valueText))"))
    }

    @Test func windowRolesExposeOnlyTheirNativeCommandCapabilities() {
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.workspaceNavigation))
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.tabs))
        #expect(MacWikiCommandCapabilities.mainWorkspace.contains(.reader))
        #expect(MacWikiCommandCapabilities.articleWindow.contains(.reader))
        #expect(MacWikiCommandCapabilities.articleWindow.contains(.inspector))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.tabs))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.workspaceNavigation))
        #expect(!MacWikiCommandCapabilities.articleWindow.contains(.libraryOrganization))
    }

    @Test func clickModifiersComeFromTheCurrentNativeEvent() throws {
        let bridge = try source("Sources/MacWiki/Utilities/SystemBridge.swift")

        #expect(bridge.contains("@MainActor private static var currentModifierFlags"))
        #expect(bridge.contains("NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags"))
        #expect(bridge.contains("currentModifierFlags.contains(.command)"))
        #expect(bridge.contains("currentModifierFlags.contains(.shift)"))
        #expect(bridge.contains("currentModifierFlags.contains(.option)"))
        #expect(!bridge.contains("CGEvent(source: nil)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
