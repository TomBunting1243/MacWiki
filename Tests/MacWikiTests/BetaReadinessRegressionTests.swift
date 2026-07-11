import Foundation
import Testing

@testable import MacWiki

@MainActor
struct BetaReadinessRegressionTests {
    @Test func webViewPoolRetentionIsUnionedByWindowOwner() {
        let pool = WebViewPool.shared
        pool.resetForTesting()

        let mainOwner = UUID()
        let articleOwner = UUID()
        let mainTab = UUID()
        let articleTab = UUID()

        pool.retain(only: [mainTab], for: mainOwner)
        pool.retain(only: [articleTab], for: articleOwner)
        #expect(pool.retainedTabIDsForTesting() == [mainTab, articleTab])
        #expect(pool.canStoreWebViewForTesting(for: mainTab) == true)

        pool.retain(only: [], for: articleOwner)
        #expect(pool.retainedTabIDsForTesting() == [mainTab])
        #expect(pool.canStoreWebViewForTesting(for: articleTab) == false)

        pool.releaseOwner(mainOwner)
        #expect(pool.retainedTabIDsForTesting().isEmpty)
        #expect(pool.canStoreWebViewForTesting(for: UUID()) == false)

        pool.releaseOwner(articleOwner)
        #expect(pool.canStoreWebViewForTesting(for: UUID()) == true)
    }

    @Test func liquidGlassChromeKeepsLegacyStorageKey() {
        #expect(AppStorageKey.Chrome.liquidGlassChrome == "tabBarLiquidGlass")
        #expect(AppStorageKey.Chrome.tabBarLiquidGlass == AppStorageKey.Chrome.liquidGlassChrome)
    }

    @Test func tabAccessibilityValueIncludesSemanticMarkers() {
        let value = TabAccessibilityStatus.value(
            isActive: true,
            isSaved: true,
            hasHighlights: true,
            isRead: false,
            showsProgress: true,
            progress: 0.62
        )

        #expect(value == "Active tab, saved, has highlights, 62% read")
    }

    @Test func persistedColumnWidthsRejectInvalidValuesAndClampToSupportedRanges() {
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(320, range: MainWindowColumnWidth.inspectorRange) == 320)
    }

    @Test func sidebarSelectableRowsUseButtonSemantics() throws {
        let source = try String(contentsOf: repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MacWiki")
            .appendingPathComponent("Views")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("ListsSidebar.swift"), encoding: .utf8)

        guard let functionRange = source.range(of: "private func sidebarSelectableRow") else {
            Issue.record("Missing sidebarSelectableRow")
            return
        }
        let functionBody = String(source[functionRange.lowerBound...])
            .components(separatedBy: "private func rootTitle")
            .first ?? ""

        #expect(functionBody.contains("Button {"))
        #expect(!functionBody.contains(".onTapGesture"))
        #expect(functionBody.contains(".accessibilityIdentifier(selection.accessibilityIdentifier)"))
        #expect(source.contains("sidebarSectionHeader(\"Explore\")"))
    }

    @Test func settingsSlidersExposeSingleAccessibleControlLabel() throws {
        let settingsControlsSource = try source("Sources/MacWiki/Views/Components/SettingsControls.swift")
        let sliderRow = sourceSection(
            settingsControlsSource,
            startingAt: "struct SettingsSliderRow",
            endingBefore: "struct ReaderTypographyPreviewView"
        )

        #expect(sliderRow.contains(".accessibilityHidden(true)"))
        #expect(sliderRow.contains("AccessibleSettingsSlider("))
        #expect(settingsControlsSource.contains("private struct AccessibleSettingsSlider: NSViewRepresentable"))
        #expect(settingsControlsSource.contains("slider.setAccessibilityTitle(title)"))
        #expect(settingsControlsSource.contains("slider.setAccessibilityLabel(title)"))
        #expect(settingsControlsSource.contains("slider.setAccessibilityValue(valueText)"))
        #expect(settingsControlsSource.contains("slider.setAccessibilityValueDescription(valueText)"))
        #expect(!sliderRow.contains(".accessibilityElement(children: .ignore)"))
    }

    @Test func inspectorResizeHandleHasKeyboardAccessibleAdjustment() throws {
        let inspectorSource = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let resizeHandle = sourceSection(
            inspectorSource,
            startingAt: "private struct SectionResizeHandle",
            endingBefore: "private struct InfoTopContentHeightPreferenceKey"
        )

        #expect(resizeHandle.contains(".accessibilityLabel(\"Resize metadata and contents sections\")"))
        #expect(resizeHandle.contains(".accessibilityValue(\"\\(Int(currentHeight.rounded())) pixels\")"))
        #expect(resizeHandle.contains(".accessibilityAdjustableAction"))
        #expect(resizeHandle.contains("case .increment:"))
        #expect(resizeHandle.contains("case .decrement:"))
        #expect(resizeHandle.contains(".accessibilityAction(named: \"Reset\", onReset)"))
        #expect(resizeHandle.contains("private func adjustHeight(by delta: CGFloat)"))
    }

    @Test func mainWindowIsPresentedOnColdLaunchWhileArticleSceneStaysValueDriven() throws {
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")
        let mainScene = sourceSection(
            appSource,
            startingAt: "Window(\"MacWiki\", id: \"main\")",
            endingBefore: "WindowGroup(\"Article\", for: Article.self)"
        )
        let articleScene = sourceSection(
            appSource,
            startingAt: "WindowGroup(\"Article\", for: Article.self)",
            endingBefore: "Settings {"
        )

        #expect(mainScene.contains("Window(\"MacWiki\", id: \"main\")"))
        #expect(mainScene.contains(".defaultLaunchBehavior(.presented)"))
        #expect(articleScene.contains(".defaultLaunchBehavior(.suppressed)"))
        #expect(appSource.contains("func applicationShouldHandleReopen"))
        #expect(appSource.contains("MacWikiRuntime.shared.presentMainWindowIfNeeded()"))
        #expect(appSource.contains("private final class MacWikiRuntime"))
        #expect(appSource.contains("existingWindow.makeKeyAndOrderFront(nil)"))
        #expect(appSource.contains("private func hasOnScreenWindow() -> Bool"))
        #expect(appSource.contains("CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)"))
        #expect(appSource.contains("NSHostingView("))
        #expect(appSource.contains("private struct MacWikiLaunchIssue: Identifiable"))
        #expect(appSource.contains("launchIssue: MacWikiLaunchIssue?"))
        #expect(appSource.contains("presentFallbackLaunchIssueIfNeeded(for: window)"))
        #expect(appSource.contains("alert.beginSheetModal(for: window)"))
    }

    @Test func revisionMetadataUnknownCacheDoesNotBlockHydrationRetry() async {
        let service = WikipediaService()
        let staleMetadata = [
            WikipediaService.MetadataItem(label: "Word count", value: "2,009 words"),
            WikipediaService.MetadataItem(label: "Last edited", value: "Unknown"),
            WikipediaService.MetadataItem(label: "First created", value: "Unknown")
        ]
        let completeMetadata = [
            WikipediaService.MetadataItem(label: "Word count", value: "2,009 words"),
            WikipediaService.MetadataItem(label: "Last edited", value: "Apr 26, 2026"),
            WikipediaService.MetadataItem(label: "First created", value: "Mar 10, 2010")
        ]

        let staleIsUnknown = await service.hasUnknownRevisionMetadata(staleMetadata)
        let completeIsUnknown = await service.hasUnknownRevisionMetadata(completeMetadata)

        #expect(staleIsUnknown)
        #expect(!completeIsUnknown)
    }

    @Test func discoverEditionAvoidsPlaceholderCopyAndDecorativeOrbBackdrop() throws {
        let root = repositoryRoot()
        let discoverRoot = root
            .appendingPathComponent("Sources")
            .appendingPathComponent("MacWiki")
            .appendingPathComponent("Views")
            .appendingPathComponent("Home")
            .appendingPathComponent("Discover")

        let discoverFiles = [
            root
                .appendingPathComponent("Sources")
                .appendingPathComponent("MacWiki")
                .appendingPathComponent("Views")
                .appendingPathComponent("Home")
                .appendingPathComponent("DiscoverNewTabPageView.swift"),
            discoverRoot.appendingPathComponent("DiscoverFeedSections.swift"),
            discoverRoot.appendingPathComponent("DiscoverMediaSupport.swift")
        ]

        for file in discoverFiles {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("Text(\"PLACEHOLDER\")"))
        }

        let newTabSource = try String(
            contentsOf: root
                .appendingPathComponent("Sources")
                .appendingPathComponent("MacWiki")
                .appendingPathComponent("Views")
                .appendingPathComponent("Home")
                .appendingPathComponent("DiscoverNewTabPageView.swift"),
            encoding: .utf8
        )
        #expect(!newTabSource.contains("RadialGradient("))
        #expect(!newTabSource.contains("Circle()"))
    }

    @Test func searchCommandUsesEmbeddedListContentsSearchOnly() throws {
        let root = repositoryRoot()
        let commandsSource = try source("Sources/MacWiki/App/MacWikiCommands.swift")
        let contentSource = try source("Sources/MacWiki/Views/ContentView.swift")
        let listsSidebarSource = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")
        let settingsNavigationSource = try source("Sources/MacWiki/Views/Components/SettingsNavigationPane.swift")

        #expect(commandsSource.contains("appState.startSearch(context: .navigation)"))
        #expect(commandsSource.contains(#".keyboardShortcut("k", modifiers: .command)"#))
        #expect(contentSource.contains(".onChange(of: appState.showSearch)"))
        #expect(contentSource.contains("revealSidebarForEmbeddedSearchIfNeeded()"))

        let sidebarBindingSync = sourceSection(
            listsSidebarSource,
            startingAt: "private var sidebarWithBindingSelectionSync",
            endingBefore: "private var sidebarWithSelectionSync"
        )
        #expect(sidebarBindingSync.contains(".onChange(of: appState.showSearch)"))
        #expect(sidebarBindingSync.contains("syncSelectionFromBindings()"))

        #expect(!contentSource.contains("QuickSearchView"))
        #expect(!settingsNavigationSource.contains("Search Presentation"))
        #expect(!settingsNavigationSource.contains("SearchPresentationMode"))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/MacWiki/Views/Home/QuickSearchView.swift").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/MacWiki/Models/SearchPresentationMode.swift").path))
    }

    @Test func articleNewWindowUsesDedicatedReaderInspectorShell() throws {
        let articleWindowSource = try source("Sources/MacWiki/Views/Shared/ArticleWindowRootView.swift")
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")

        #expect(articleWindowSource.contains("HSplitView"))
        #expect(articleWindowSource.contains("ReaderView()"))
        #expect(articleWindowSource.contains("InspectorColumnView("))
        #expect(articleWindowSource.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"))
        #expect(articleWindowSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!appSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot()
                .appendingPathComponent("Sources/MacWiki/Views/Shared/WindowChromeConfigurator.swift")
                .path
        ))
        #expect(!articleWindowSource.contains("NavigationSplitView"))
        #expect(!articleWindowSource.contains("MainWindowShell"))
        #expect(!articleWindowSource.contains("ListsColumnView"))
        #expect(!articleWindowSource.contains("DirectoryColumnView"))
        #expect(appSource.contains("ArticleWindowRootView(initialArticle:"))
    }

    @Test func sidebarListControlsAndRecentsMetadataStayScoped() throws {
        let sidebarSource = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")
        let directorySource = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let articleRowsSource = try source("Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift")

        let libraryMenu = sourceSection(
            sidebarSource,
            startingAt: "private var sidebarLibraryMenu",
            endingBefore: "private func rootRowLabel"
        )
        #expect(libraryMenu.contains("Button(\"New List\")"))
        #expect(libraryMenu.contains("Button(\"New Folder\")"))
        #expect(!libraryMenu.contains("New Label"))
        #expect(!libraryMenu.contains("New Tag"))

        #expect(sidebarSource.contains("help: \"New Label\""))
        #expect(sidebarSource.contains("help: \"New Tag\""))

        let listRow = sourceSection(
            sidebarSource,
            startingAt: "private struct ListRowView",
            endingBefore: "/// Label row for sidebar"
        )
        #expect(listRow.contains("SwiftUI.Label(\"Rename\", systemImage: \"pencil\")"))
        #expect(listRow.contains("SwiftUI.Label(\"Move to Folder\", systemImage: \"folder\")"))
        #expect(listRow.contains("onMoveToFolder(nil)"))
        #expect(listRow.contains("ForEach(availableAreas)"))

        #expect(directorySource.contains("alwaysShowsLabelMetadata: true"))
        #expect(directorySource.contains("showsListMembership: true"))
        #expect(directorySource.contains("tags: tags"))
        #expect(articleRowsSource.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(articleRowsSource.contains(".strokeBorder(rowStroke, lineWidth: 0.75)"))
    }

    @Test func articleToolbarRendersAsCustomReaderChromeWithCurrentPillStyling() throws {
        let shellSource = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let readerColumnSource = try source("Sources/MacWiki/Views/Columns/ReaderColumnView.swift")
        let readerSource = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let toolbarSource = try source("Sources/MacWiki/Views/Shared/ReaderArticleToolbar.swift")
        let navigationSource = try source("Sources/MacWiki/App/AppState+NavigationTabs.swift")
        let toolbarBody = sourceSection(
            toolbarSource,
            startingAt: "var body: some View",
            endingBefore: "private var navigationPill"
        )

        #expect(readerColumnSource.contains("ReaderArticleToolbar()"))
        #expect(!shellSource.contains(".toolbar {"))
        #expect(shellSource.contains("if appState.directoryColumnVisible"))
        #expect(shellSource.contains("else if appState.listsSidebarVisible"))
        #expect(shellSource.contains("MainSidebarReaderShell("))
        #expect(shellSource.contains("MainReaderOnlyShell("))
        #expect(shellSource.contains("MainNavigationShell("))
        #expect(shellSource.contains("ColumnMotion.readerOnlyVisibility"))
        #expect(shellSource.contains(".transition(shellTransition)"))
        #expect(shellSource.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(readerColumnSource.contains("readerTopChromeBackground"))
        #expect(readerColumnSource.contains("ReaderTabLaneBackground()"))
        #expect(toolbarBody.contains("GeometryReader"))
        #expect(toolbarBody.contains("ToolbarDensity(width: proxy.size.width)"))
        #expect(toolbarSource.contains("private enum ToolbarDensity"))
        #expect(toolbarSource.contains("private struct ToolbarVisibility"))
        #expect(toolbarSource.contains("case compact"))
        #expect(toolbarSource.contains("case narrow"))
        #expect(toolbarSource.contains("let visibility = ToolbarVisibility(width: proxy.size.width)"))
        #expect(toolbarSource.contains("var hasOverflowActions: Bool"))
        #expect(toolbarSource.contains("showsBackForward = width >= 620"))
        #expect(toolbarSource.contains("showsReaderStyle = width >= 700"))
        #expect(toolbarSource.contains("showsShare = width >= 760"))
        #expect(toolbarSource.contains("showsPageViews = width >= 860"))
        #expect(toolbarSource.contains("showsOpenInBrowser = width >= 940"))
        #expect(toolbarBody.contains("HStack(spacing: density.clusterSpacing)"))
        #expect(toolbarBody.contains("listContentsPill"))
        #expect(toolbarBody.contains("navigationSearchPill"))
        #expect(!toolbarBody.contains("searchPill"))
        #expect(toolbarSource.contains("articleStatePill"))
        #expect(toolbarSource.contains("articleToolsPill"))
        #expect(toolbarSource.contains("shareBrowserOverflowPill"))
        #expect(toolbarSource.contains("inspectorPill"))
        #expect(toolbarSource.contains("openInBrowserControl"))
        #expect(!toolbarSource.contains("centeredArticleCluster"))
        #expect(!toolbarSource.contains("activeArticleTitle"))
        #expect(!toolbarSource.contains("titleMaxWidth("))
        #expect(!toolbarSource.contains("toolbarTitle"))
        #expect(toolbarBody.contains("Spacer(minLength: 16)"))
        #expect(!toolbarBody.contains("articleActionsPill"))
        #expect(toolbarBody.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(toolbarBody.contains(".ignoresSafeArea(.container, edges: .top)"))
        #expect(toolbarSource.contains("MacWikiGlassGroup(spacing: density.clusterSpacing)"))
        #expect(toolbarSource.contains("toolbarPill"))
        #expect(!toolbarSource.contains("titlePill"))
        #expect(toolbarSource.contains("toolbarIconButton"))
        #expect(toolbarSource.contains("case listContents"))
        #expect(toolbarSource.contains("appState.directoryColumnVisible"))
        #expect(toolbarSource.contains("appState.toggleDirectoryColumnVisibility()"))
        #expect(toolbarSource.contains("sidebar.squares.leading"))
        #expect(toolbarSource.contains("leadingPadding(density: density, proxy: proxy)"))
        #expect(toolbarSource.contains("trafficLightReservedWidth"))
        #expect(navigationSource.contains("listContentsColumnVisible = false"))
        #expect(navigationSource.contains("listContentsColumnVisible = true"))
        #expect(navigationSource.contains("func toggleNavigationColumnsVisibility()"))
        #expect(toolbarSource.contains("withAnimation(ColumnMotion.readerOnlyVisibility)"))
        #expect(toolbarSource.contains("var buttonSize: CGFloat"))
        #expect(toolbarSource.contains("var dividerHeight: CGFloat"))
        #expect(toolbarSource.contains("toolbarDivider(density: density)"))
        #expect(!toolbarSource.contains("minimumScaleFactor(0.68)"))
        #expect(!toolbarSource.contains("density.titleMinWidth"))
        #expect(!toolbarSource.contains("density.titleIdealWidth"))
        #expect(!toolbarSource.contains(".fixedSize(horizontal: true, vertical: false)"))
        #expect(toolbarSource.contains(".glassEffect(.regular.interactive(), in: .capsule)"))
        #expect(!toolbarSource.contains(".glassEffect(.regular.interactive(), in: .rect(cornerRadius: 8))"))
        #expect(toolbarSource.contains(".fill(.thinMaterial)"))
        #expect(toolbarSource.contains("Color(nsColor: .controlBackgroundColor)"))
        #expect(toolbarSource.contains(".symbolRenderingMode(.monochrome)"))
        #expect(toolbarSource.contains(".allowsHitTesting(isEnabled)"))
        #expect(toolbarSource.contains("Color.primary.opacity"))
        #expect(toolbarSource.contains(".buttonStyle(.plain)"))
        #expect(toolbarSource.contains("showingMorePopover"))
        #expect(toolbarSource.contains("morePopover(visibility: visibility)"))
        #expect(toolbarSource.contains(".scaleEffect(isInteractive && !reduceMotion ? 1.012 : 1)"))
        #expect(toolbarSource.contains(".animation(.easeOut(duration: 0.14), value: isHovered)"))
        #expect(!toolbarSource.contains("ControlGroup"))
        #expect(!toolbarSource.contains("Menu {"))
        #expect(!toolbarSource.contains("ToolbarItem(placement: .principal)"))
        #expect(!toolbarSource.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(!toolbarSource.contains("ToolbarItem(placement: .topBarTrailing)"))
        #expect(!shellSource.contains(".frame(minWidth: 520, idealWidth: 980, maxWidth: .infinity)"))
        #expect(toolbarSource.contains("appState.goBack()"))
        #expect(toolbarSource.contains("appState.goForward()"))
        #expect(toolbarSource.contains("appState.startSearch(context: .navigation)"))
        #expect(toolbarSource.contains("appState.toggleInspectorVisibility()"))
        #expect(navigationSource.contains("func toggleDirectoryColumnVisibility()"))
        #expect(navigationSource.contains("navigationSplitViewVisibilityBeforeReaderOnly"))
        #expect(toolbarSource.contains(".fixedSize()"))
        #expect(readerSource.contains("resolvedTopObscuredHeight - 44"))
    }

    @Test func customLiquidGlassChromeUsesSharedGroupingAndPolicy() throws {
        let floatingGlassSources = [
            "Sources/MacWiki/Views/Components/FindOnPageBarView.swift",
            "Sources/MacWiki/Views/Components/HighlightToolbar.swift",
            "Sources/MacWiki/Views/Components/WikiHopOverlay.swift",
            "Sources/MacWiki/Views/Components/WebView/WebViewLinkHoverPreviewPane.swift",
            "Sources/MacWiki/Views/Reader/ReaderView.swift"
        ]

        for path in floatingGlassSources {
            let source = try source(path)
            #expect(source.contains("MacWikiGlassGroup("))
            #expect(source.contains("AppStorageKey.Chrome.liquidGlassChrome"))
            #expect(!source.contains("AppStorageKey.Chrome.tabBarLiquidGlass"))
            #expect(source.contains("MacWikiGlassRuntime.usesNativeGlass("))
            #expect(source.contains("isEnabled: liquidGlassChrome"))
        }

        let tabBarSource = try source("Sources/MacWiki/Views/Components/TabBarView.swift")
        #expect(tabBarSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))
        #expect(!tabBarSource.contains("usesNativeStripGlassCells"))

        let laneSource = try source("Sources/MacWiki/Views/Shared/ColumnTopBar.swift")
        #expect(laneSource.contains("ReaderTabLaneBackground"))
        #expect(laneSource.contains(".fill(.thinMaterial)"))
        #expect(laneSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))
    }

    @Test func readerFindUsesMacWikiFindBarOnCurrentMacOS() throws {
        let readerSource = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        #expect(readerSource.contains("FindOnPageBarView("))
        #expect(readerSource.contains("private var usesNativeFindNavigator: Bool"))
        #expect(readerSource.contains("return false"))
        #expect(readerSource.contains("findOnPageRequestID: usesNativeFindNavigator ? nil : appState.pendingFindOnPageRequest?.requestID"))
    }

    @Test func settingsDescribeLiquidGlassAsGlobalChrome() throws {
        let settingsPaneSource = try source("Sources/MacWiki/Views/Components/SettingsChromePane.swift")
        let settingsCatalogSource = try source("Sources/MacWikiSettingsCatalog/SettingsCatalog.swift")

        #expect(settingsPaneSource.contains("Liquid Glass Chrome"))
        #expect(!settingsPaneSource.contains("Liquid Glass Tab Bar"))
        #expect(settingsPaneSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))

        #expect(settingsCatalogSource.contains("Liquid Glass Chrome"))
        #expect(settingsCatalogSource.contains(#"storageKey: "tabBarLiquidGlass""#))
        #expect(settingsCatalogSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))
    }

    @Test func inspectorHighlightsAndReferencesKeepGlassCompactBehavior() throws {
        let highlightListSource = try source("Sources/MacWiki/Views/Components/HighlightListView.swift")
        let highlightRowSource = try source("Sources/MacWiki/Views/Components/HighlightRowView.swift")
        let referenceListSource = try source("Sources/MacWiki/Views/Inspector/ReferenceListView.swift")
        let referenceRowSource = try source("Sources/MacWiki/Views/Inspector/ReferenceRowView.swift")
        let referenceExportBarSource = try source("Sources/MacWiki/Views/Inspector/ReferenceExportBarView.swift")

        #expect(highlightListSource.contains("HighlightDisplayFilter.visibleHighlights"))
        #expect(highlightListSource.contains(".fill(.ultraThinMaterial)"))
        #expect(highlightRowSource.contains("private var labelRow"))
        #expect(highlightRowSource.contains("private var actionRow"))
        #expect(highlightRowSource.contains("Image(systemName: isExpanded ? \"chevron.up\" : \"chevron.down\")"))
        #expect(highlightRowSource.contains("systemImage: \"pencil\""))
        #expect(highlightRowSource.contains("systemImage: \"arrow.down.left\""))

        #expect(referenceListSource.contains("@State private var suppressNextReferenceScroll = false"))
        #expect(referenceListSource.contains(".scrollIndicators(.visible)"))
        #expect(referenceListSource.contains("if suppressNextReferenceScroll"))
        #expect(referenceListSource.contains(".overlay(alignment: .bottom)"))
        #expect(referenceListSource.contains("ReferenceExportBarView("))
        #expect(referenceListSource.contains(".fill(.ultraThinMaterial)"))
        #expect(referenceRowSource.contains("private var labelRow"))
        #expect(referenceRowSource.contains("private var actionRow"))
        #expect(referenceRowSource.contains("isExpanded.toggle()"))
        #expect(referenceExportBarSource.contains(".fill(.ultraThinMaterial)"))
    }

    @Test func hoverPreviewRightClickStillRoutesThroughLinkContextMenu() throws {
        let webScript = try source("Sources/MacWiki/Resources/WebView.js")
        let routingSource = try source("Sources/MacWiki/Views/Components/WebView/WebView+Routing.swift")
        let contextMenuSource = try source("Sources/MacWiki/Views/Components/WebView/WebView+ContextMenus.swift")

        let linkContextHandler = sourceSection(
            webScript,
            startingAt: "document.addEventListener('contextmenu', function (e) {",
            endingBefore: "// Link hover previews"
        )
        #expect(linkContextHandler.contains("window._macwikiHideLinkHoverPreview()"))
        #expect(linkContextHandler.contains("window.webkit.messageHandlers.linkRightClicked.postMessage"))
        #expect(linkContextHandler.contains("url: target.href"))

        #expect(routingSource.contains("handleLinkContextRequest(data)"))
        #expect(routingSource.contains("presentNativeLinkContextMenu(for: request)"))
        #expect(contextMenuSource.contains("Open in New Window"))
        #expect(contextMenuSource.contains("openLinkFromContextMenuInNewWindow"))
    }

    @Test func formerPublicReleaseFlowIsExplicitlyRetired() throws {
        let releaseScript = try source("scripts/release_beta.sh")

        #expect(releaseScript.contains("RETIRED: automated public release"))
        #expect(releaseScript.contains("INTERNAL_BETA_QUALITY_PROGRAM.md"))
        #expect(releaseScript.range(of: "exit 2")!.lowerBound < releaseScript.range(of: "ROOT_DIR=")!.lowerBound)
    }

    @Test func settingsPopupQAHonorsConfiguredAppName() throws {
        let settingsQAScript = try source("scripts/qa_settings_popups_smoke.sh")

        #expect(settingsQAScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(settingsQAScript.contains("ObjC.import('stdlib')"))
        #expect(settingsQAScript.contains("ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki'"))
        #expect(settingsQAScript.contains("ObjC.unwrap($.getenv('APP_PID'))"))
        #expect(settingsQAScript.contains("se.processes.whose({ unixId: appPid })()"))
        #expect(settingsQAScript.contains("qa_launch_exact"))
        #expect(settingsQAScript.contains("popups.forEach((popup, index) =>"))
        #expect(settingsQAScript.contains("expected >=2 visible popup controls"))
        #expect(!settingsQAScript.contains("const appName = 'MacWiki';"))
        #expect(!settingsQAScript.contains("se.processes.byName(appName)"))
        #expect(!settingsQAScript.contains("Search Presentation"))
    }

    @Test func packagedArtifactsIncludeBuildTraceabilityPlist() throws {
        let packageScript = try source("scripts/package_beta_app.sh")

        #expect(packageScript.contains("BUILD_INFO_PATH=\"$APP_PATH/Contents/Resources/BuildInfo.plist\""))
        #expect(packageScript.contains("git -C \"$ROOT_DIR\" rev-parse HEAD"))
        #expect(packageScript.contains("git -C \"$ROOT_DIR\" branch --show-current"))
        #expect(packageScript.contains("git -C \"$ROOT_DIR\" status --porcelain --untracked-files=all"))
        #expect(packageScript.contains("xcodebuild -version"))
        #expect(packageScript.contains("swift --version 2>&1 | head -n 1"))
        #expect(packageScript.contains("PackageTimestampUTC"))
        #expect(packageScript.contains("plist_add_string \"$BUILD_INFO_PATH\" \"GitCommit\" \"$SOURCE_COMMIT\""))
        #expect(packageScript.contains("plist_add_string \"$BUILD_INFO_PATH\" \"GitDirty\" \"false\""))
        #expect(packageScript.contains("SourceExecutableSHA256"))
        #expect(packageScript.contains("PackagedExecutableSHA256"))
        #expect(packageScript.contains("AppTreeSHA256"))
        #expect(packageScript.contains("ZipSHA256"))
        #expect(packageScript.contains("--expected-executable-sha256"))
        #expect(packageScript.contains("require_clean_git_tree"))
        #expect(packageScript.contains("rm -f \"$ZIP_PATH\""))
    }

    @Test func legacyPublicBetaDocsAreExplicitlyRetired() throws {
        let releaseChecklist = try source("RELEASE_BETA_CHECKLIST.md")
        let qaMatrix = try source("PUBLIC_BETA_QA_MATRIX.md")

        #expect(releaseChecklist.contains("RETIRED — historical reference only"))
        #expect(qaMatrix.contains("RETIRED — historical reference only"))
        #expect(releaseChecklist.contains("INTERNAL_BETA_QUALITY_PROGRAM.md"))
        #expect(qaMatrix.contains("scripts/internal_beta_preflight.sh"))
    }

    @Test func internalBetaPreflightIsTheOnlyActiveReleaseGate() throws {
        let readme = try source("README.md")
        let preflight = try source("scripts/internal_beta_preflight.sh")
        let retiredPreflight = try source("scripts/preflight_beta_release.sh")

        #expect(readme.contains("INTERNAL_BETA_QUALITY_PROGRAM.md"))
        #expect(readme.contains("./scripts/internal_beta_preflight.sh"))
        #expect(!readme.contains("./scripts/preflight_beta_release.sh"))
        #expect(!readme.contains("./scripts/release_beta.sh"))
        #expect(preflight.contains("Internal-beta preflight requires a clean committed worktree"))
        #expect(preflight.contains("Internal-beta preflight requires Xcode 27 and macOS SDK 27"))
        #expect(preflight.contains("swift package clean"))
        #expect(preflight.contains("BinaryMinimumOS"))
        #expect(preflight.contains("BinarySDK"))
        #expect(preflight.contains("otool -l"))
        #expect(preflight.contains("--expected-executable-sha256"))
        #expect(preflight.contains("--result-file"))
        #expect(preflight.contains("--ad-hoc-sign"))
        #expect(retiredPreflight.contains("RETIRED: public-beta preflight"))
    }

    @Test func canonicalAndInternalCandidateVersionsStayOnTheOnePointZeroLine() throws {
        let infoPlist = repositoryRoot().appendingPathComponent("Sources/MacWiki/Info.plist")
        let info = try #require(NSDictionary(contentsOf: infoPlist) as? [String: Any])
        let service = try source("Sources/MacWiki/Services/WikipediaService.swift")
        let discoverHarness = try source("scripts/qa_discover_scroll_time_machine.sh")
        let preflight = try source("scripts/internal_beta_preflight.sh")

        #expect(info["CFBundleShortVersionString"] as? String == "1.0")
        #expect(service.contains(#"?? "1.0""#))
        #expect(!service.contains(#"?? "0.5.0""#))
        #expect(discoverHarness.contains("MacWiki/1.0"))
        #expect(preflight.contains(#"CANONICAL_VERSION"#))
        #expect(preflight.contains(#"^1\.0(-internal\.[0-9]+)?$"#))
    }

    @Test func releaseBuildsEmbedTheSelectedSDKWithoutRaisingTheDeploymentFloor() throws {
        let helper = try source("scripts/lib/release_build.sh")
        let preflight = try source("scripts/internal_beta_preflight.sh")
        let packager = try source("scripts/package_beta_app.sh")

        #expect(helper.contains("xcrun --sdk macosx --show-sdk-version"))
        #expect(helper.contains("-Xlinker=-platform_version"))
        #expect(helper.contains("-Xlinker=\"$minimum_macos\""))
        #expect(helper.contains("-Xlinker=\"$sdk_version\""))
        #expect(preflight.contains("macwiki_release_build_args \"26.0\""))
        #expect(preflight.contains("swift build -c release \"${MACWIKI_RELEASE_BUILD_ARGS[@]}\""))
        #expect(packager.contains("LSMinimumSystemVersion"))
        #expect(packager.contains("macwiki_release_build_args"))
        #expect(packager.contains("if [[ \"$SKIP_BUILD\" -eq 1 ]]"))
        #expect(packager.contains("BIN_DIR=\"$(swift build -c release --show-bin-path)\""))
    }

    @Test func aboutPanelLetsAppKitRenderTheBuildNumberOnce() throws {
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")

        #expect(appSource.contains(".applicationVersion: shortVersion"))
        #expect(!appSource.contains(#".applicationVersion: "Version"#))
    }

    @Test func readerOpenProfileHarnessCanTargetPackagedCandidate() throws {
        let profileScript = try source("scripts/profile_reader_open.sh")

        #expect(profileScript.contains("--app-binary PATH"))
        #expect(profileScript.contains("APP_BINARY=\"${APP_BINARY:-$REPO_ROOT/.build/debug/MacWiki}\""))
        #expect(profileScript.contains("--app-binary)"))
        #expect(profileScript.contains("APP_BINARY=\"$2\""))
        #expect(profileScript.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
        #expect(profileScript.contains("CFFIXED_USER_HOME=$QA_HOME"))
        #expect(!profileScript.contains("pkill -x"))
        #expect(!profileScript.contains("APP_BINARY=\"$REPO_ROOT/.build/debug/MacWiki\""))
    }

    @Test func auditCaptureHarnessesCanTargetPackagedCandidate() throws {
        let captureScript = try source("scripts/capture_macwiki_window.sh")
        let captureSetScript = try source("scripts/capture_macwiki_audit_set.sh")

        #expect(captureScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(captureScript.contains("app_binary=\"${APP_BIN:-$app_binary_default}\""))
        #expect(captureScript.contains("APP_PID=\"${APP_PID:-}\""))
        #expect(captureScript.contains("APP_PID is required for a targeted capture"))
        #expect(captureScript.contains("actual_binary=\"$(ps -p \"$APP_PID\" -o comm="))
        #expect(captureScript.contains("kCGWindowOwnerPID"))
        #expect(captureScript.contains("optionOnScreenOnly"))
        #expect(captureScript.contains("/^[0-9]+$/"))
        #expect(!captureScript.contains("screencapture -x -R"))
        #expect(captureScript.contains("mkdir -p /tmp/macwiki-audit"))
        #expect(!captureScript.contains("pgrep -x"))

        #expect(captureSetScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(captureSetScript.contains("APP_BIN=\"${APP_BIN:-$app_binary_default}\""))
        #expect(captureSetScript.contains("APP_PID=\"$QA_APP_PID\" \"$capture_window_script\""))
        #expect(captureSetScript.contains("qa_launch_exact"))
        #expect(captureSetScript.contains("App binary: \\`$APP_BIN\\`"))
        #expect(!captureSetScript.contains("app_binary=\"$repo_root/.build/arm64-apple-macosx/debug/MacWiki\""))
    }

    @Test func discoverQAHarnessCanTargetPackagedCandidate() throws {
        let discoverScript = try source("scripts/qa_discover_scroll_time_machine.sh")

        #expect(discoverScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(discoverScript.contains("APP_BIN_DEFAULT=\"$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki\""))
        #expect(discoverScript.contains("APP_BIN=\"${APP_BIN:-$APP_BIN_DEFAULT}\""))
        #expect(!discoverScript.contains("pkill -x"))
        #expect(discoverScript.contains("MACWIKI_QA_PID=\"${QA_APP_PID:-}\" swift - <<'SWIFT'"))
        #expect(discoverScript.contains("== targetPid"))
        #expect(discoverScript.contains("tell application (item 1 of argv) to activate"))
        #expect(discoverScript.contains("APP_PID=\"$QA_APP_PID\" \"$capture_script\""))
        #expect(discoverScript.contains("App binary: \\`$APP_BIN\\`"))
        #expect(!discoverScript.contains("DerivedData/MacWiki-hgaamxiclllsfufsrrsbkmjdjcle"))
        #expect(!discoverScript.contains("pkill -x MacWiki"))
        #expect(!discoverScript.contains("tell application \"MacWiki\" to activate"))
    }

    @Test func readingListQAHarnessesUsePortableAppBinaryDefaults() throws {
        let folderCollapseScript = try source("scripts/qa_folder_collapse_selected_list.sh")
        let nestedRenameScript = try source("scripts/qa_nested_folder_rename.sh")

        for script in [folderCollapseScript, nestedRenameScript] {
            #expect(script.contains("REPO_ROOT=\"$(cd \"$SCRIPT_DIR/..\" && pwd)\""))
            #expect(script.contains("APP_BIN_DEFAULT=\"$REPO_ROOT/.build/arm64-apple-macosx/debug/MacWiki\""))
            #expect(script.contains("APP_BIN_FALLBACK=\"$REPO_ROOT/.build/debug/MacWiki\""))
            #expect(script.contains("APP_BIN=\"${APP_BIN:-$APP_BIN_DEFAULT}\""))
            #expect(script.contains("if [[ ! -x \"$APP_BIN\" && -x \"$APP_BIN_FALLBACK\" ]]; then"))
            #expect(script.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
            #expect(script.contains("qa_launch_exact"))
            #expect(!script.contains("pkill -x"))
            #expect(!script.contains("WORKDIR=\"/Users/tombunting/Developer/MacWiki\""))
            #expect(!script.contains("APP_BIN=\"${APP_BIN:-$WORKDIR/.build/debug/MacWiki}\""))
        }
    }

    @Test func mutatingQAHarnessesRequireIsolatedStateAndExactProcessIdentity() throws {
        let safetyLibrary = try source("scripts/lib/qa_process_safety.sh")
        let scriptNames = [
            "scripts/profile_reader_open.sh",
            "scripts/qa_context_menu_ocr.sh",
            "scripts/qa_folder_collapse_selected_list.sh",
            "scripts/qa_nested_folder_rename.sh",
            "scripts/qa_discover_scroll_time_machine.sh",
            "scripts/qa_sidebar_search_width_classes.sh",
            "scripts/qa_settings_popups_smoke.sh",
            "scripts/capture_macwiki_audit_set.sh"
        ]

        #expect(safetyLibrary.contains("HOME=\"$QA_HOME\" CFFIXED_USER_HOME=\"$QA_HOME\" \"$APP_BIN\""))
        #expect(safetyLibrary.contains("ps -p \"$QA_APP_PID\" -o comm="))
        #expect(safetyLibrary.contains("Refusing to run while $APP_NAME PID"))

        for scriptName in scriptNames {
            let script = try source(scriptName)
            #expect(script.contains("qa_process_safety.sh"))
            #expect(!script.contains("pkill -x"))
            #expect(!script.contains("open -n \"$APP_BIN\""))
            #expect(!script.contains("$HOME/Library/Application Support/default.store"))
        }
    }

    @Test func widthClassHarnessUsesReachableVerifiedWindowSizes() throws {
        let script = try source("scripts/qa_sidebar_search_width_classes.sh")
        let captureScript = try source("scripts/capture_macwiki_window.sh")

        #expect(script.contains("WIDTH_PRESETS_CSV=\"${WIDTH_PRESETS_CSV:-1040,1400,1760}\""))
        #expect(script.contains("Verified actual window width"))
        #expect(script.contains("Could not establish and verify target window width"))
        #expect(!script.contains("236,288,360"))
        #expect(!script.contains("esc badge"))
        #expect(captureScript.contains("for attempt in 1 2 3"))
        #expect(captureScript.contains("after 3 attempts"))
    }

    @Test func sidebarSearchOwnsItsNativeTopSafeArea() throws {
        let source = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")

        #expect(source.contains(".safeAreaPadding(.top)"))
        #expect(source.contains(".padding(.top, TabBarChromeStyle.strip.height)"))
        #expect(!source.contains("topObscuredHeight"))
    }

    @Test func mainWindowShellScopesAlternateLayoutsAndUsesKeyPathBindings() throws {
        let source = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")

        #expect(source.contains("private struct MainNavigationShell: View"))
        #expect(source.contains("private struct MainSidebarReaderShell: View"))
        #expect(source.contains("private struct MainReaderOnlyShell: View"))
        #expect(source.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(!source.contains("Binding(\n"))
    }

    @Test func optionClickSaveUsesNativeMacOSFormControls() throws {
        let sheetSource = try source("Sources/MacWiki/Views/Components/OptionClickSaveSheet.swift")
        let commandsSource = try source("Sources/MacWiki/App/MacWikiCommands.swift")

        #expect(sheetSource.contains("Form {"))
        #expect(sheetSource.contains(".formStyle(.grouped)"))
        #expect(sheetSource.contains("Picker(\"List\""))
        #expect(sheetSource.contains("Picker(\"Label\""))
        #expect(sheetSource.contains("Picker(\"Tag\""))
        #expect(!sheetSource.contains("selectorButton("))
        #expect(!sheetSource.contains("tagRowBackground("))
        #expect(commandsSource.contains("CommandGroup(after: .newItem)"))
        #expect(commandsSource.contains("Button(\"Save Article...\")"))
        #expect(!commandsSource.contains("CommandGroup(replacing: .saveItem)"))
    }

    @Test func qaHarnessesAvoidMachineSpecificRepositoryPaths() throws {
        let scriptNames = [
            "scripts/qa_context_menu_ocr.sh",
            "scripts/qa_folder_collapse_selected_list.sh",
            "scripts/qa_nested_folder_rename.sh",
            "scripts/qa_discover_scroll_time_machine.sh"
        ]

        for scriptName in scriptNames {
            let script = try source(scriptName)
            #expect(!script.contains("WORKDIR=\"/Users/tombunting/Developer/MacWiki\""))
            #expect(!script.contains("DerivedData/MacWiki-hgaamxiclllsfufsrrsbkmjdjcle"))
        }
    }

    @Test func saveToListPopoverExposesEveryListInScrollableContent() throws {
        let source = try source("Sources/MacWiki/Views/Components/SaveToListPopover.swift")

        #expect(source.contains("ScrollView"))
        #expect(source.contains("ForEach(lists)"))
        #expect(source.contains(".frame(maxHeight: 280)"))
        #expect(!source.contains("lists.prefix"))
        #expect(!source.contains("more..."))
    }

    @Test func discoverDirectoryAndReaderShareOneSessionDate() throws {
        let appStateSource = try source("Sources/MacWiki/App/AppState.swift")
        let directorySource = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let readerSource = try source("Sources/MacWiki/Views/Home/DiscoverNewTabPageView.swift")

        #expect(appStateSource.contains("var selectedDiscoverDate = Date()"))
        #expect(!directorySource.contains("@State private var selectedDiscoverDate"))
        #expect(directorySource.contains("get { appState.selectedDiscoverDate }"))
        #expect(directorySource.contains("selection: selectedDiscoverDateBinding"))
        #expect(readerSource.contains("screenModel.selectedDiscoverDate = appState.selectedDiscoverDate"))
        #expect(readerSource.contains(".onChange(of: appState.selectedDiscoverDate)"))
        #expect(readerSource.contains("appState.selectedDiscoverDate = newDate"))
        #expect(readerSource.components(separatedBy: "await Task.yield()").count == 3)
        #expect(readerSource.contains("guard screenModel.selectedDiscoverDate == newDate else { return }"))
        #expect(readerSource.contains("guard appState.selectedDiscoverDate == newDate else { return }"))
    }

    @Test func discoverDirectoryDefersDateReloadBeyondTheTableDelegateAction() throws {
        let source = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let reload = sourceSection(
            source,
            startingAt: "private func queueDiscoverLoadDebounced(",
            endingBefore: "private func shiftDiscoverDate(days:"
        )

        #expect(reload.contains("delayNanoseconds: UInt64 = 170_000_000"))
        #expect(reload.contains("try? await Task.sleep(nanoseconds: delayNanoseconds)"))
        #expect(reload.contains("guard !Task.isCancelled else { return }"))
    }

    @Test func discoverDirectoryAvoidsTheNSTableViewBackedListDuringFeedReplacement() throws {
        let source = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let surface = sourceSection(
            source,
            startingAt: "private var directoryScrollSurface",
            endingBefore: "private static let discoverFeedDateFormatter"
        )

        #expect(surface.contains("if rootSelection == .discover"))
        #expect(surface.contains("ScrollView"))
        #expect(surface.contains("LazyVStack"))
        #expect(surface.contains("discoverSections()"))
        #expect(surface.contains("else {\n            List {"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func sourceSection(
        _ source: String,
        startingAt startNeedle: String,
        endingBefore endNeedle: String
    ) -> String {
        guard let start = source.range(of: startNeedle) else {
            Issue.record("Missing source section start: \(startNeedle)")
            return ""
        }
        let tail = source[start.lowerBound...]
        guard let end = tail.range(of: endNeedle) else {
            return String(tail)
        }
        return String(tail[..<end.lowerBound])
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
