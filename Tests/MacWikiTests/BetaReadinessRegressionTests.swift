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
        let windowChromeSource = try source("Sources/MacWiki/Views/Shared/WindowChromeConfigurator.swift")

        #expect(articleWindowSource.contains("HSplitView"))
        #expect(articleWindowSource.contains("ReaderView()"))
        #expect(articleWindowSource.contains("InspectorColumnView("))
        #expect(articleWindowSource.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"))
        #expect(articleWindowSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(articleWindowSource.contains(".configuredMacWikiWindowChrome()"))
        #expect(appSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(appSource.contains(".configuredMacWikiWindowChrome()"))
        #expect(windowChromeSource.contains("navigationSplitView.toggleSidebar"))
        #expect(windowChromeSource.contains("SwiftUI.splitViewSeparator"))
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
        #expect(shellSource.contains("sidebarReaderShell"))
        #expect(shellSource.contains("readerOnlyShell"))
        #expect(shellSource.contains("navigationShell(columnVisibility:"))
        #expect(shellSource.contains("ColumnMotion.readerOnlyVisibility"))
        #expect(shellSource.contains(".transition(shellTransition)"))
        #expect(shellSource.contains(".inspector(isPresented: inspectorPresented)"))
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
        #expect(toolbarSource.contains("appState.sidebarVisible"))
        #expect(toolbarSource.contains("appState.toggleNavigationColumnsVisibility()"))
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

    @Test func releaseFlowPackagesFreshArtifactWhenPreflightIsSkipped() throws {
        let releaseScript = try source("scripts/release_beta.sh")
        let skippedPreflightBlock = sourceSection(
            releaseScript,
            startingAt: "else\n  echo \"Preflight skipped; packaging a fresh signed/notarized artifact before release.\"",
            endingBefore: "ZIP_PATH=\"${ZIP_PATH:-$(latest_zip_path)}\""
        )

        #expect(releaseScript.contains("latest_zip_path()"))
        #expect(releaseScript.contains("package_release_artifact()"))
        #expect(skippedPreflightBlock.contains("package_release_artifact"))
        #expect(releaseScript.contains("ZIP_PATH=\"dist/MacWiki-${PACKAGE_VERSION}-build${BUILD_NUMBER}-DRY-RUN.zip\""))
        #expect(!releaseScript.contains("gh release upload \"$VERSION\" \"dist/MacWiki-${PACKAGE_VERSION}-build${BUILD_NUMBER}-\""))
    }

    @Test func settingsPopupQAHonorsConfiguredAppName() throws {
        let settingsQAScript = try source("scripts/qa_settings_popups_smoke.sh")

        #expect(settingsQAScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(settingsQAScript.contains("ObjC.import('stdlib')"))
        #expect(settingsQAScript.contains("ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki'"))
        #expect(!settingsQAScript.contains("const appName = 'MacWiki';"))
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
        #expect(packageScript.contains("plist_add_string \"$BUILD_INFO_PATH\" \"GitCommit\" \"$GIT_COMMIT\""))
        #expect(packageScript.contains("plist_add_string \"$BUILD_INFO_PATH\" \"GitDirty\" \"$GIT_DIRTY\""))
    }

    @Test func publicBetaDocsRequireTraceablePackageAndStorageRecoveryQA() throws {
        let releaseChecklist = try source("RELEASE_BETA_CHECKLIST.md")
        let qaMatrix = try source("PUBLIC_BETA_QA_MATRIX.md")

        #expect(releaseChecklist.contains("BuildInfo.plist"))
        #expect(releaseChecklist.contains("GitDirty=false"))
        #expect(releaseChecklist.contains("Print :GitCommit"))
        #expect(releaseChecklist.contains("Print :GitDirty"))

        #expect(qaMatrix.contains("Settings Reading sliders expose one useful VoiceOver control each"))
        #expect(qaMatrix.contains("visible main window on cold launch and after Dock reopen"))
        #expect(qaMatrix.contains("Storage Recovery Mode"))
        #expect(qaMatrix.contains("BuildInfo.plist"))
        #expect(qaMatrix.contains("GitDirty=false"))
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
