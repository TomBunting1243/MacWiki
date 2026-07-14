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

    @Test func articleListRowsExposeArticleIdentityAndIndependentReadAction() throws {
        let rowSource = try source("Sources/MacWiki/Views/Sidebar/Directory/ArticleListAccessibility.swift")
        #expect(!rowSource.contains(".accessibilityElement(children: .contain)"))
        #expect(rowSource.contains("let onToggleRead: (() -> Void)?"))
        #expect(rowSource.contains(".accessibilityInputLabels([title])"))
        #expect(rowSource.contains(".accessibilityValue(\"\\(title), \\(isRead ?"))
        #expect(rowSource.contains("\"Read\" : \"Unread\""))
        #expect(rowSource.contains("Use the context menu for read status and organization actions."))
        #expect(rowSource.contains(".accessibilityAddTraits(.isButton)"))
        #expect(rowSource.contains(".accessibilityAction {"))
        #expect(rowSource.contains("named: Text(\"Toggle Read Status\")"))
        #expect(!rowSource.contains("accessibilityRepresentation"))

        let contextMenuSource = try source("Sources/MacWiki/Views/Components/ArticleContextMenuContent.swift")
        #expect(contextMenuSource.contains("ReadStateSync.applyReadState("))
        #expect(!contextMenuSource.contains("appState.updateReadState(forTitle: article.title"))

        let itemSource = try source("Sources/MacWiki/Views/Sidebar/Directory/DirectoryArticleRowViews.swift")
        #expect(itemSource.contains(".onTapGesture(perform: onTap)"))
        #expect(itemSource.contains(".accessibilityLabel(isRead ? \"Mark as unread\" : \"Mark as read\")"))
        #expect(itemSource.contains(".accessibilityHidden(true)"))
        #expect(!itemSource.contains("Button(action: onTap)"))

        let progressSource = try source("Sources/MacWiki/Views/Components/ReadProgressIndicator.swift")
        #expect(progressSource.contains("PieSlice(progress: fillProgress)"))
        #expect(!progressSource.contains("if fillProgress"))
        #expect(progressSource.components(separatedBy: ".animation(").count == 2)

        let modelSource = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchSurfaceModel.swift")
        #expect(modelSource.contains("private struct DerivedState"))
        #expect(modelSource.contains("func refreshDerivedState("))
        #expect(modelSource.contains("derivedState = DerivedState("))

        let searchSource = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")
        #expect(searchSource.contains(".task(id: searchSurfaceFingerprint)"))
        #expect(searchSource.contains("model.refreshDerivedState("))
        #expect(searchSource.contains("Task { @MainActor in"))
        #expect(searchSource.contains("await Task.yield()"))

        let directorySource = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        #expect(directorySource.contains(".task(id: isSidebarSearchPresented ? nil : articleIndexesFingerprint)"))

        let harness = try source("scripts/qa_article_row_secondary_window.sh")
        #expect(harness.contains("qa_prepare_isolated_home"))
        #expect(harness.contains("qa_assert_no_conflicting_processes"))
        #expect(harness.contains("qa_launch_candidate"))
        #expect(harness.contains("qa_assert_candidate_manifest_matches_executable \"$BUILD_INFO_PLIST\""))
        #expect(harness.contains("ATTRIBUTEGRAPH_CYCLE_COUNT"))

        let runner = try source("scripts/ax_article_row_secondary_window.swift")
        #expect(runner.contains("hasReadStateAction(for: updated.0, named: toggleReadStatusAction)"))
        #expect(runner.contains("customAction(titled: title, on: row)"))
        #expect(runner.contains("menuItem(titled: \"Open in New Window\""))
        #expect(runner.contains("windows(in: application).count == 2"))
        #expect(runner.contains("articleWindowToolbars.count == 1"))
        #expect(runner.contains("expectedSecondaryToolbarLabels"))
        #expect(runner.contains("\"Mark as Unread\""))
        #expect(runner.contains("\"Reader Style\""))
        #expect(runner.contains("\"Hide Inspector\""))
        #expect(runner.contains("runtimeDiagnosticCheckpoints"))
        #expect(runner.contains("recordRuntimeDiagnostics(\"marked read\")"))
        #expect(runner.contains("recordRuntimeDiagnostics(\"restored unread\")"))
    }

    @Test func persistedColumnWidthsRejectInvalidValuesAndClampToSupportedRanges() {
        let source = try? source("Sources/MacWiki/Views/Shared/PersistedColumnWidth.swift")
        #expect(MainWindowColumnWidth.clampedStorageValue(.nan, range: MainWindowColumnWidth.sidebarRange) == nil)
        #expect(MainWindowColumnWidth.clampedStorageValue(120, range: MainWindowColumnWidth.sidebarRange) == 176)
        #expect(MainWindowColumnWidth.clampedStorageValue(480, range: MainWindowColumnWidth.directoryRange) == 420)
        #expect(MainWindowColumnWidth.clampedStorageValue(260, range: MainWindowColumnWidth.inspectorRange) == 270)
        #expect(MainWindowColumnWidth.clampedStorageValue(320, range: MainWindowColumnWidth.inspectorRange) == 320)
        #expect(MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: true,
            directoryVisible: true,
            inspectorVisible: true
        ) == 1_229)
        #expect(MainWindowLayout.minimumContentWidth(
            listsSidebarVisible: false,
            directoryVisible: false,
            inspectorVisible: false
        ) == MainWindowLayout.minimumReaderWidth)
        #expect(source?.contains(".task(id: proxy.size.width)") == true)
        #expect(source?.contains("Task.sleep(for: .milliseconds(200))") == true)
        #expect(source?.contains(".onChange(of: proxy.size.width)") == false)
    }

    @Test func sidebarSelectableRowsUseButtonSemantics() throws {
        let sidebarSource = try String(contentsOf: repositoryRoot()
            .appendingPathComponent("Sources")
            .appendingPathComponent("MacWiki")
            .appendingPathComponent("Views")
            .appendingPathComponent("Sidebar")
            .appendingPathComponent("ListsSidebar.swift"), encoding: .utf8)

        guard let functionRange = sidebarSource.range(of: "private func sidebarSelectableRow") else {
            Issue.record("Missing sidebarSelectableRow")
            return
        }
        let functionBody = String(sidebarSource[functionRange.lowerBound...])
            .components(separatedBy: "private func rootTitle")
            .first ?? ""

        #expect(functionBody.contains("Button {"))
        #expect(!functionBody.contains(".onTapGesture"))
        #expect(functionBody.contains("accessibilityLabel: String"))
        #expect(functionBody.contains(".accessibilityLabel(accessibilityLabel)"))
        #expect(functionBody.contains(".accessibilityIdentifier(selection.accessibilityIdentifier)"))
        #expect(sidebarSource.contains("accessibilityLabel: label.name"))
        #expect(sidebarSource.contains("accessibilityLabel: tag.name"))
        #expect(sidebarSource.contains("accessibilityLabel: list.name"))
        #expect(sidebarSource.contains("SidebarCollectionAccessibilityButton("))
        let nativeCollectionButton = try source("Sources/MacWiki/Views/Sidebar/SidebarCollectionAccessibilityButton.swift")
        #expect(nativeCollectionButton.contains("NSButton(title: title"))
        #expect(nativeCollectionButton.contains("button.setAccessibilityLabel(title)"))
        #expect(nativeCollectionButton.contains("button.setAccessibilityIdentifier(identifier)"))
        #expect(nativeCollectionButton.contains("button.menu = coordinator.makeMenu()"))
        #expect(nativeCollectionButton.contains("title: \"Change Color\""))
        #expect(nativeCollectionButton.contains("title: \"Delete\""))
        #expect(sidebarSource.contains("sidebarSectionHeader(\"Explore\")"))
        #expect(sidebarSource.contains("@State private var collectionsSnapshot: ListsSidebarSnapshot?"))
        #expect(sidebarSource.contains("collectionsSnapshot ?? liveCollectionsSnapshot"))
        #expect(sidebarSource.contains("private var collectionsSnapshotFingerprint: Int"))
        #expect(sidebarSource.contains(".task(id: collectionsSnapshotFingerprint)"))
        #expect(sidebarSource.contains("refreshCollectionsSnapshot()"))
        #expect(!sidebarSource.contains(".onChange(of: collectionsSnapshotFingerprint)"))
    }

    @Test func highlightNoteEditorHasStableAccessibilityIdentity() throws {
        let source = try source("Sources/MacWiki/Views/Components/HighlightRowView.swift")
        #expect(source.contains(".accessibilityLabel(\"Highlight note\")"))
        #expect(source.contains(".accessibilityIdentifier(\"highlight-note-editor\")"))
        #expect(source.contains("Button(action: activateHighlightRow)"))
        #expect(source.contains("Section(\"Change Color\")"))
        #expect(!source.contains(".onTapGesture(perform: activateHighlightRow)"))
        #expect(!source.contains(".accessibilityAddTraits(.isButton)"))
    }

    @Test func folderAccessibilityIdentityDoesNotOverrideNestedListIdentity() throws {
        let sidebarSource = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")
        let areaRow = sourceSection(
            sidebarSource,
            startingAt: "private struct AreaRowView",
            endingBefore: "/// Label row for sidebar"
        )
        let disclosureLabel = sourceSection(
            areaRow,
            startingAt: "} label: {",
            endingBefore: ".tag(SidebarSelectionID.area(area.id))"
        )

        #expect(disclosureLabel.contains(".accessibilityIdentifier(SidebarSelectionID.area(area.id).accessibilityIdentifier)"))
        #expect(!areaRow.contains(#".accessibilityIdentifier("area-row-\(area.name)")"#))
        #expect(sidebarSource.contains("SidebarCollapseSelectionGuard.collapseWouldHideSelectedList("))
        #expect(sidebarSource.contains("setRecentsSelection()"))
        #expect(areaRow.contains("onExpansionChange(area, newValue)"))
        #expect(!areaRow.contains("area.isExpanded = newValue"))
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

    @Test func highlightColorButtonsExposeNamesAndSelectionState() throws {
        let source = try source("Sources/MacWiki/Views/Components/HighlightToolbar.swift")
        let colorPicker = sourceSection(
            source,
            startingAt: "private var colorPickerView",
            endingBefore: "private var actionGroup"
        )

        #expect(colorPicker.contains(".accessibilityLabel(\"Highlight \\(color.rawValue.lowercased())\")"))
        #expect(colorPicker.contains(".accessibilityValue(selectedColor == color ? \"Selected\" : \"\")"))
        #expect(colorPicker.contains(".accessibilityHint(\"Creates a \\(color.rawValue.lowercased()) highlight\")"))
    }

    @Test func iconOnlyOrganizationControlsExposeNamesAndValues() throws {
        let newList = try source("Sources/MacWiki/Views/Components/NewListSheet.swift")
        let newFolder = try source("Sources/MacWiki/Views/Components/NewAreaSheet.swift")
        let labelDetail = try source("Sources/MacWiki/Views/Components/LabelDetailSheet.swift")
        let symbolPicker = try source("Sources/MacWiki/Views/Components/SFSymbolPicker.swift")
        let addToList = try source("Sources/MacWiki/Views/Components/AddToListSheet.swift")
        let saveToList = try source("Sources/MacWiki/Views/Components/SaveToListPopover.swift")
        let sidebar = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")
        let emptyCollectionButton = try source("Sources/MacWiki/Views/Sidebar/SidebarEmptyCollectionButton.swift")
        let symbolActionButton = try source("Sources/MacWiki/Views/Components/AccessibleSymbolActionButton.swift")
        let settingsControls = try source("Sources/MacWiki/Views/Components/SettingsControls.swift")
        let tagDetail = try source("Sources/MacWiki/Views/Components/TagDetailSheet.swift")

        #expect(newList.contains("accessibilityLabel: \"Choose list icon\""))
        #expect(newList.contains("accessibilityValue: selectedIcon"))
        #expect(newFolder.contains("accessibilityLabel: \"Choose folder icon\""))
        #expect(newFolder.contains("accessibilityValue: selectedIcon"))
        #expect(labelDetail.contains("accessibilityLabel: \"Choose label color\""))
        #expect(labelDetail.contains("accessibilityValue: selectedColor.rawValue"))
        #expect(labelDetail.contains("accessibilityValue: selectedColor == color ? \"Selected\" : \"\""))
        #expect(newList.contains("AccessibleActionButton(\"Cancel\", keyEquivalent: \"\\u{1b}\")"))
        #expect(newFolder.contains("AccessibleActionButton(\"Cancel\", keyEquivalent: \"\\u{1b}\")"))
        #expect(labelDetail.contains("AccessibleActionButton(\"Cancel\", keyEquivalent: \"\\u{1b}\")"))
        #expect(tagDetail.contains("AccessibleActionButton(\"Cancel\", keyEquivalent: \"\\u{1b}\")"))
        #expect(newList.contains(".disabled(trimmedName.isEmpty)"))
        #expect(newFolder.contains(".disabled(trimmedName.isEmpty)"))
        #expect(labelDetail.contains(".disabled(trimmedName.isEmpty)"))
        #expect(tagDetail.contains(".disabled(trimmedName.isEmpty)"))
        #expect(settingsControls.contains("struct AccessibleActionButton: NSViewRepresentable"))
        #expect(settingsControls.contains("button.keyEquivalent = keyEquivalent"))
        #expect(settingsControls.contains("button.setAccessibilityTitle(title)"))
        #expect(symbolActionButton.contains("button.setAccessibilityTitle(accessibilityLabel)"))
        #expect(symbolActionButton.contains("button.setAccessibilityLabel(accessibilityLabel)"))
        #expect(symbolActionButton.contains("button.setAccessibilityValue(accessibilityValue)"))
        #expect(symbolPicker.contains(".accessibilityLabel(\"Clear symbol search\")"))
        #expect(symbolPicker.contains(".accessibilityLabel(\"Select \\(symbol)\")"))
        #expect(symbolPicker.contains(".accessibilityValue(selectedSymbol == symbol ? \"Selected\" : \"\")"))
        #expect(addToList.contains("NavigationStack"))
        #expect(addToList.contains(".searchable(text: $searchText, prompt: \"Search Lists\")"))
        #expect(addToList.contains("ToolbarItem(placement: .cancellationAction)"))
        #expect(addToList.contains("isSaved ? \"Already saved\" : \"\\(list.articles.count) articles\""))
        #expect(saveToList.contains(".accessibilityValue(isSaved ? \"Saved\" : \"Not saved\")"))
        #expect(sidebar.contains(".accessibilityLabel(help)"))
        #expect(sidebar.contains(".accessibilityLabel(\"New List or Folder\")"))
        #expect(sidebar.contains("title: \"New Label\""))
        #expect(sidebar.contains("identifier: \"sidebar-new-label-empty\""))
        #expect(sidebar.contains("title: \"New Tag\""))
        #expect(sidebar.contains("identifier: \"sidebar-new-tag-empty\""))
        #expect(sidebar.contains("SidebarEmptyCollectionButton("))
        #expect(emptyCollectionButton.contains("button.setAccessibilityLabel(title)"))
        #expect(emptyCollectionButton.contains("button.setAccessibilityIdentifier(identifier)"))
    }

    @Test func iconOnlyReaderAndFilterControlsExposeState() throws {
        let searchHeader = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchHeaderView.swift")
        let directory = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")

        #expect(searchHeader.contains(".accessibilityLabel(\"Unread only\")"))
        #expect(searchHeader.contains(".accessibilityValue(model.readFilter == .unread ? \"Enabled\" : \"Disabled\")"))
        #expect(directory.contains(".accessibilityLabel(\"Unread only\")"))
        #expect(directory.contains(".accessibilityValue(unreadFilterEnabled ? \"Enabled\" : \"Disabled\")"))
        #expect(reader.contains(".accessibilityLabel(\"Dismiss finished-reading prompt\")"))
    }

    @Test func iconOnlySearchAndTagActionsExposeNames() throws {
        let directory = try source("Sources/MacWiki/Views/Sidebar/DirectoryView.swift")
        let labelArticles = try source("Sources/MacWiki/Views/Sidebar/Directory/LabelArticlesView.swift")
        let tagArticles = try source("Sources/MacWiki/Views/Sidebar/Directory/TagArticlesView.swift")
        let searchResults = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchResultsView.swift")
        let discoverSearch = try source("Sources/MacWiki/Views/Home/Discover/DiscoverSearchBarView.swift")
        let wikiHop = try source("Sources/MacWiki/Views/Components/WikiHopOverlay.swift")

        #expect(directory.contains(".accessibilityLabel(\"Clear tag filter\")"))
        #expect(labelArticles.contains(".accessibilityLabel(\"Clear tag filter\")"))
        #expect(tagArticles.contains(".accessibilityLabel(\"Clear tag filter\")"))
        #expect(searchResults.contains(".accessibilityLabel(\"Clear filter\")"))
        #expect(discoverSearch.contains(".accessibilityLabel(\"Refresh Discover\")"))
        #expect(discoverSearch.contains(".accessibilityValue(discoverFeedStore.isLoading ? \"Refreshing\" : \"Ready\")"))
        #expect(discoverSearch.contains(".accessibilityLabel(\"Clear Search\")"))
        #expect(wikiHop.contains(".accessibilityLabel(\"Give Up Wiki-Hop\")"))
    }

    @Test func inspectorInfoUsesOneReachableNativeScrollSurface() throws {
        let inspectorSource = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let infoContent = sourceSection(
            inspectorSource,
            startingAt: "private var infoContent",
            endingBefore: "private func infoTopModules"
        )

        #expect(infoContent.contains("ScrollViewReader"))
        #expect(infoContent.contains("ScrollView {"))
        #expect(infoContent.contains("LazyVStack"))
        #expect(!infoContent.contains(".clipped()"))
        #expect(!inspectorSource.contains("SectionResizeHandle"))
        #expect(!inspectorSource.contains("infoSplitFallbackBudget"))
    }

    @Test func mainWindowHasASingleSwiftUISceneOwnerAndNativeLaunchPolicy() throws {
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
        #expect(appSource.contains("func applicationWillFinishLaunching"))
        #expect(!appSource.contains("func applicationDidFinishLaunching"))
        #expect(!appSource.contains("func applicationShouldHandleReopen"))
        #expect(!appSource.contains("MacWikiRuntime"))
        #expect(!appSource.contains("MacWikiLaunchPresentation"))
        #expect(!appSource.contains("MacWikiWindowSelection"))
        #expect(!appSource.contains("NSWindow("))
        #expect(!appSource.contains("NSHostingView("))
        #expect(!appSource.contains("NSHostingController("))
        #expect(!appSource.contains("sceneBridgingOptions"))
        #expect(!appSource.contains("CGWindowListCopyWindowInfo("))
        #expect(appSource.contains("private struct MacWikiLaunchIssue: Identifiable"))
        #expect(appSource.contains("launchIssue: MacWikiLaunchIssue?"))
        #expect(appSource.components(separatedBy: ".defaultAppStorage(MacWikiDefaults.current)").count - 1 == 3)
        #expect(!appSource.contains("UserDefaults.standard"))
    }

    @Test func mainWindowLifecycleHarnessIsBoundedIsolatedAndNative() throws {
        let harness = try source("scripts/qa_main_window_lifecycle.sh")
        let driver = try source("scripts/ax_main_window_lifecycle.swift")

        #expect(harness.contains("lib/qa_process_safety.sh"))
        #expect(harness.contains("qa_assert_candidate_manifest_matches_executable"))
        #expect(harness.contains("Set APP_BIN to a packaged candidate executable."))
        #expect(harness.contains("qa_prepare_isolated_home"))
        #expect(harness.contains("qa_run_command_with_timeout 90"))
        #expect(harness.contains("trap cleanup EXIT INT TERM"))
        #expect(harness.contains("EXC_BAD_ACCESS"))
        #expect(harness.contains("(.cycles | length) == 5"))
        #expect(harness.contains(".stableSampleCount >= 20"))
        #expect(harness.contains("5 --audit-close"))
        #expect(harness.contains(".closeAudit.processResidentAfterClose == true"))
        #expect(harness.contains(".closeAudit.reopenedSamePID == true"))
        #expect(driver.contains("stableObservationSeconds: TimeInterval = 3.25"))
        #expect(driver.contains("residencyObservationSeconds: TimeInterval = 2.5"))
        #expect(driver.contains("kAXMinimizeButtonAttribute"))
        #expect(driver.contains("kAXCloseButtonAttribute"))
        #expect(driver.contains("kAXToolbarRole"))
        #expect(driver.contains("CFEqual(reopenedWindow, initialWindow)"))
        #expect(driver.contains("/usr/bin/open"))
        #expect(driver.contains("Cycle count must be between one and five."))
        #expect(!driver.contains("CGEvent("))
        #expect(!driver.contains("mouseCursorPosition"))
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

        #expect(!articleWindowSource.contains("HSplitView"))
        #expect(articleWindowSource.contains("ReaderView()"))
        #expect(articleWindowSource.contains("InspectorColumnView("))
        #expect(articleWindowSource.contains(".inspector(isPresented: $appState.inspectorVisible)"))
        #expect(articleWindowSource.contains(".inspectorColumnWidth("))
        #expect(articleWindowSource.contains(".focusedSceneValue(\\.macWikiInspectorCommandsAvailable, true)"))
        #expect(!articleWindowSource.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"))
        #expect(articleWindowSource.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(articleWindowSource.contains(".toolbar(id: ArticleWindowReaderToolbarIdentifier.configuration)"))
        #expect(articleWindowSource.contains("ArticleWindowReaderToolbar("))
        #expect(articleWindowSource.contains("ArticleWindowReaderCommandPresenter("))
        #expect(articleWindowSource.contains(".focusedSceneValue(\\.macWikiCommandModelContext, modelContext)"))
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

        #expect(sidebarSource.contains("@State private var collectionsSnapshot: ListsSidebarSnapshot?"))
        #expect(sidebarSource.contains("collectionsSnapshot ?? liveCollectionsSnapshot"))
        #expect(sidebarSource.contains(".task(id: collectionsSnapshotFingerprint)"))
        #expect(sidebarSource.contains("refreshCollectionsSnapshot()"))

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

    @Test func articleToolbarUsesNativeCustomizableWindowToolbar() throws {
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")
        let contentSource = try source("Sources/MacWiki/Views/ContentView.swift")
        let shellSource = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let nativeSplitSource = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")
        let splitControllerSource = try source("Sources/MacWiki/Views/Shared/WorkspaceSplitViewController.swift")
        let toolbarLayoutSource = try source("Sources/MacWiki/Views/Shared/ReaderToolbarLayout.swift")
        let toolbarSource = try source("Sources/MacWiki/Views/Shared/ReaderToolbarController.swift")
        let toolbarItemsSource = try source("Sources/MacWiki/Views/Shared/ReaderToolbarController+Items.swift")
        let toolbarPopoverSource = try source("Sources/MacWiki/Views/Shared/ReaderToolbarPopoverPresenter.swift")
        let readerColumnSource = try source("Sources/MacWiki/Views/Columns/ReaderColumnView.swift")
        let tabBarSource = try source("Sources/MacWiki/Views/Components/TabBarView.swift")
        let inspectorColumnSource = try source("Sources/MacWiki/Views/Columns/InspectorColumnView.swift")
        let commandSource = try source("Sources/MacWiki/App/MacWikiCommands.swift")
        let navigationSource = try source("Sources/MacWiki/App/AppState+NavigationTabs.swift")

        #expect(!contentSource.contains(".toolbar(id:"))
        #expect(!contentSource.contains("ReaderArticleToolbar()"))
        #expect(!contentSource.contains("WindowToolbarCustomizationPersistenceBridge()"))
        #expect(!readerColumnSource.contains("ReaderArticleToolbar()"))
        #expect(toolbarSource.contains("final class ReaderToolbarController: NSObject"))
        #expect(toolbarSource.contains("NSToolbarDelegate"))
        #expect(toolbarSource.contains("NSSharingServicePickerToolbarItemDelegate"))
        #expect(toolbarItemsSource.contains("NSTrackingSeparatorToolbarItem("))
        #expect(toolbarItemsSource.contains("dividerIndex: 0"))
        #expect(toolbarItemsSource.contains("dividerIndex: 1"))
        #expect(toolbarItemsSource.contains("dividerIndex: 2"))
        #expect(toolbarSource.contains("toolbar.allowsUserCustomization = true"))
        #expect(toolbarSource.contains("toolbar.autosavesConfiguration = true"))
        #expect(toolbarSource.contains("toolbar.isVisible = snapshot.articleID != nil"))
        #expect(toolbarSource.contains("if environment.appState.currentArticle == nil"))
        #expect(toolbarSource.contains("toolbar.allowsDisplayModeCustomization = false"))
        #expect(toolbarSource.contains("toolbar.displayMode = .iconOnly"))
        #expect(toolbarSource.contains("toolbarImmovableItemIdentifiers"))
        #expect(toolbarSource.contains("canBeInsertedAt index: Int"))
        #expect(toolbarLayoutSource.contains("main-window-reader-scoped-toolbar-v15"))
        #expect(toolbarLayoutSource.contains(".macWikiSidebarDirectoryBoundary"))
        #expect(toolbarLayoutSource.contains(".macWikiDirectoryReaderBoundary"))
        #expect(toolbarLayoutSource.contains(".macWikiReaderInspectorBoundary"))
        #expect(toolbarLayoutSource.contains("readerIdentifiers"))
        #expect(toolbarLayoutSource.contains("identifier == .space"))
        #expect(toolbarLayoutSource.contains("identifier == .flexibleSpace"))
        #expect(toolbarLayoutSource.contains("index > leftBoundary && index <= rightBoundary"))
        #expect(appSource.contains(".windowToolbarStyle(.unifiedCompact(showsTitle: false))"))
        #expect(!appSource.contains("ContentView()\n                .toolbar(removing: .title)"))
        #expect(!appSource.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"))

        #expect(shellSource.contains("directoryVisible: $appState.directoryColumnVisible"))
        #expect(shellSource.contains("MainWorkspaceShell("))
        #expect(shellSource.contains("NativeWorkspaceSplitView("))
        #expect(shellSource.contains("sidebarRevision: workspaceAppearanceRevision"))
        #expect(shellSource.contains("directoryRevision: directoryContentRevision"))
        #expect(shellSource.contains("readerRevision: workspaceAppearanceRevision"))
        #expect(shellSource.contains("inspectorRevision: workspaceAppearanceRevision"))
        #expect(nativeSplitSource.contains("lastDirectoryRevision"))
        #expect(nativeSplitSource.contains("lastReaderRevision"))
        #expect(nativeSplitSource.contains("lastInspectorRevision"))
        #expect(nativeSplitSource.contains("controller.configureReaderToolbar(environment: readerToolbarEnvironment)"))
        #expect(splitControllerSource.contains("final class WorkspaceSplitViewController: NSSplitViewController"))
        #expect(splitControllerSource.contains("readerToolbarController?.installIfPossible()"))
        #expect(shellSource.contains(".id(\"main-reader-column\")"))
        #expect(!shellSource.contains(".transition(shellTransition)"))
        #expect(shellSource.contains("inspectorVisible: $appState.inspectorVisible"))
        #expect(shellSource.contains("InspectorColumnView()"))
        #expect(!inspectorColumnSource.contains("SidebarPaneBackground()"))
        #expect(!shellSource.contains(".inspector(isPresented:"))
        #expect(!shellSource.contains("Task.sleep(for: .milliseconds(80))"))
        #expect(!contentSource.contains("ColumnMotion.sidebarVisibility"))
        #expect(!contentSource.contains("performAnimation(PanelMotion.sidebarToggle)"))
        #expect(!readerColumnSource.contains("readerTopChromeBackground"))
        #expect(readerColumnSource.contains("TabBarView("))
        #expect(tabBarSource.contains("ReaderTabLaneBackground()"))
        #expect(toolbarItemsSource.contains("environment.appState.toggleListsSidebarVisibility()"))
        #expect(toolbarItemsSource.contains("environment.appState.toggleDirectoryColumnVisibility()"))
        #expect(toolbarItemsSource.contains("sidebar.squares.leading"))
        #expect(navigationSource.contains("directoryColumnVisible.toggle()"))
        #expect(!navigationSource.contains("func toggleNavigationColumnsVisibility()"))
        #expect(toolbarItemsSource.contains("environment.appState.goBack()"))
        #expect(toolbarItemsSource.contains("environment.appState.goForward()"))
        #expect(toolbarItemsSource.contains("environment.appState.startSearch(context: .navigation)"))
        #expect(toolbarItemsSource.contains("environment.appState.toggleInspectorVisibility()"))
        #expect(toolbarSource.contains("snapshot.inspectorVisible ? \"Hide Inspector\" : \"Show Inspector\""))
        #expect(contentSource.contains(".focusedSceneValue(\\.macWikiInspectorCommandsAvailable, true)"))
        #expect(commandSource.contains("@FocusedValue(\\.macWikiInspectorCommandsAvailable)"))
        #expect(commandSource.contains("inspectorCommandsAvailable != true"))
        #expect(commandSource.contains("|| !supports(.inspector)"))
        #expect(toolbarPopoverSource.contains("SaveToListPopover(article: article)"))
        #expect(toolbarPopoverSource.contains("ReaderStylePopover()"))
        #expect(toolbarPopoverSource.contains("SidebarPageViewsPopoverContent("))
        #expect(toolbarPopoverSource.contains("popover.show(relativeTo: item)"))
        #expect(toolbarItemsSource.contains("ReadStateSync.applyReadState("))
        #expect(toolbarItemsSource.contains("environment.openURL(article.url)"))
        #expect(toolbarItemsSource.contains("return [article.url as NSURL]"))
        #expect(navigationSource.contains("func toggleDirectoryColumnVisibility()"))
        #expect(!navigationSource.contains("navigationSplitViewVisibilityBeforeReaderOnly"))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot()
                .appendingPathComponent("Sources/MacWiki/Views/Shared/ReaderArticleToolbar.swift")
                .path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot()
                .appendingPathComponent("Sources/MacWiki/Views/Shared/WindowToolbarCustomizationPersistenceBridge.swift")
                .path
        ))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot()
                .appendingPathComponent("Sources/MacWiki/Views/Shared/ReaderToolbarChrome.swift")
                .path
        ))
    }

    @Test func customLiquidGlassChromeUsesSharedGroupingAndPolicy() throws {
        let singleSurfaceGlassSources = [
            "Sources/MacWiki/Views/Components/FindOnPageBarView.swift",
            "Sources/MacWiki/Views/Components/HighlightToolbar.swift",
            "Sources/MacWiki/Views/Components/WikiHopOverlay.swift",
            "Sources/MacWiki/Views/Components/WebView/WebViewLinkHoverPreviewPane.swift"
        ]

        for path in singleSurfaceGlassSources {
            let source = try source(path)
            #expect(!source.contains("MacWikiGlassGroup("))
            #expect(source.contains("AppStorageKey.Chrome.liquidGlassChrome"))
            #expect(!source.contains("AppStorageKey.Chrome.tabBarLiquidGlass"))
            #expect(source.contains("MacWikiGlassRuntime.usesNativeGlass("))
            #expect(source.contains("isEnabled: liquidGlassChrome"))
            #expect(source.contains(".glassEffect("))
            #expect(source.contains("reduceTransparency"))
        }

        let tabBarSource = try source("Sources/MacWiki/Views/Components/TabBarView.swift")
        let tabItemSource = try source("Sources/MacWiki/Views/Components/ReaderTabItemView.swift")
        let tabAccessorySource = try source("Sources/MacWiki/Views/Components/ReaderTabAccessoryCluster.swift")
        let readerSource = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let glassGroupSource = try source("Sources/MacWiki/Views/Shared/MacWikiGlass.swift")

        #expect(tabBarSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))
        #expect(tabBarSource.contains("MacWikiGlassGroup(spacing: tabSpacing)"))
        #expect(!tabBarSource.contains("usesNativeStripGlassCells"))
        #expect(tabItemSource.contains(".regular.tint(tint).interactive()"))
        #expect(tabItemSource.contains("MacWikiGlassRuntime.usesNativeGlass("))
        #expect(!tabItemSource.contains(".compositingGroup()"))
        #expect(tabAccessorySource.contains("MacWikiGlassGroup(spacing: 8)"))
        #expect(tabAccessorySource.contains(".regular.interactive()"))
        #expect(readerSource.contains("MacWikiGlassGroup(spacing: 7)"))
        #expect(readerSource.contains("usesNativeReaderGlass"))
        #expect(readerSource.contains("if accessibilityPersonalization.reduceTransparency"))
        #expect(!readerSource.contains(".compositingGroup()"))
        #expect(glassGroupSource.contains("GlassEffectContainer(spacing: spacing)"))
        #expect(!glassGroupSource.contains("@AppStorage"))

        let laneSource = try source("Sources/MacWiki/Views/Shared/ColumnTopBar.swift")
        #expect(laneSource.contains("ReaderTabLaneBackground"))
        #expect(laneSource.contains(".fill(.thinMaterial)"))
        #expect(laneSource.contains("AppStorageKey.Chrome.liquidGlassChrome"))
    }

    @Test func customChromeHonorsTransparencyAndContrastPersonalization() throws {
        let columnChrome = try source("Sources/MacWiki/Views/Shared/ColumnTopBar.swift")
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")
        let qaPersonalizationSource = try source("Sources/MacWiki/App/MacWikiQAPersonalization.swift")

        #expect(appSource.contains(".windowToolbarStyle(.unifiedCompact(showsTitle: false))"))
        #expect(!appSource.contains(".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"))

        #expect(columnChrome.contains("struct SidebarPaneBackground"))
        #expect(columnChrome.contains("struct ReaderTabLaneBackground"))
        #expect(columnChrome.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceTransparency)"))
        #expect(columnChrome.contains("@Environment(\\.macWikiAccessibilityPersonalization.colorSchemeContrast)"))
        #expect(columnChrome.contains("if liquidGlassChrome && reduceTransparency"))
        #expect(columnChrome.contains("colorSchemeContrast == .increased"))

        // Main, both Article window branches, and Settings must inherit the
        // same trusted accessibility-personalization environment.
        #expect(appSource.components(separatedBy: ".macWikiQAAccessibilityEnvironment()").count == 5)
        #expect(qaPersonalizationSource.contains("MacWikiQAEnvironment.trustedSuiteName"))
        #expect(qaPersonalizationSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(qaPersonalizationSource.contains("@Environment(\\.accessibilityReduceTransparency)"))
        #expect(qaPersonalizationSource.contains("@Environment(\\.accessibilityDifferentiateWithoutColor)"))
        #expect(qaPersonalizationSource.contains("@Environment(\\.colorSchemeContrast)"))
        #expect(qaPersonalizationSource.contains("qa.accessibility-personalization"))
    }

    @Test func readerFindUsesMacWikiFindBarOnCurrentMacOS() throws {
        let readerSource = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        #expect(readerSource.contains("FindOnPageBarView("))
        #expect(!readerSource.contains(".findNavigator("))
        #expect(readerSource.contains("findOnPageRequestID: appState.pendingFindOnPageRequest?.requestID"))
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
        let inspectorSource = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let inspectorHeaderSource = try source("Sources/MacWiki/Views/Inspector/InspectorHeaderBar.swift")
        let modeViewsSource = try source("Sources/MacWiki/Views/Inspector/InspectorModeViews.swift")
        let highlightListSource = try source("Sources/MacWiki/Views/Components/HighlightListView.swift")
        let highlightRowSource = try source("Sources/MacWiki/Views/Components/HighlightRowView.swift")
        let referenceListSource = try source("Sources/MacWiki/Views/Inspector/ReferenceListView.swift")
        let referenceRowSource = try source("Sources/MacWiki/Views/Inspector/ReferenceRowView.swift")
        let referenceExportBarSource = try source("Sources/MacWiki/Views/Inspector/ReferenceExportBarView.swift")

        #expect(inspectorHeaderSource.contains("Picker(\"Inspector mode\", selection: $selection)"))
        #expect(inspectorHeaderSource.contains(".pickerStyle(.segmented)"))
        #expect(!inspectorSource.contains("private struct InspectorModeControl"))
        #expect(inspectorSource.contains("transaction.animation = nil"))
        #expect(inspectorSource.contains("InspectorHeaderBar(selection: $appState.inspectorMode)"))
        #expect(inspectorSource.contains("switch appState.inspectorMode"))
        #expect(inspectorSource.contains("@State private var showStaleHighlights = true"))
        #expect(inspectorSource.contains("@State private var showArchivedHighlights = false"))
        #expect(inspectorSource.contains("@State private var selectedReferenceIDs: Set<String> = []"))
        #expect(inspectorSource.contains("InspectorNotesModeView("))
        #expect(inspectorSource.contains("InspectorReferencesModeView("))
        #expect(modeViewsSource.contains("@Binding var showStaleHighlights: Bool"))
        #expect(modeViewsSource.contains("@Binding var showArchivedHighlights: Bool"))
        #expect(modeViewsSource.contains("@Binding var selectedReferenceIDs: Set<String>"))
        #expect(inspectorSource.components(separatedBy: ".task(id: appState.currentArticle?.title)").count - 1 == 1)
        #expect(inspectorSource.firstRange(of: ".task(id: appState.currentArticle?.title)")!.lowerBound < inspectorSource.firstRange(of: "private var infoContent")!.lowerBound)
        #expect(!inspectorSource.contains("InfoTopContentHeightPreferenceKey"))
        #expect(!inspectorSource.contains("infoTopContentHeight"))

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
        #expect(referenceListSource.contains(".safeAreaInset(edge: .top"))
        #expect(referenceListSource.contains(".safeAreaInset(edge: .bottom"))
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

    @Test func readerKeyboardPagingRemainsNativeToWebKit() throws {
        let webScript = try source("Sources/MacWiki/Resources/WebView.js")
        let keyboardHandler = sourceSection(
            webScript,
            startingAt: "window.addEventListener('keydown', function (e) {",
            endingBefore: "function refreshScrollMetricsAfterResize()"
        )

        #expect(!webScript.contains("handleKeyboardPageScroll"))
        #expect(!webScript.contains("keyboardPageStepDistance"))
        #expect(!keyboardHandler.contains("preventDefault"))
        #expect(keyboardHandler.contains("WebKit owns native keyboard paging"))
        #expect(keyboardHandler.contains("keyboardPagingUntil = Date.now() + 500"))
    }

    @Test func formerPublicReleaseFlowIsExplicitlyRetired() throws {
        let releaseScript = try source("scripts/release_beta.sh")

        #expect(releaseScript.contains("RETIRED: automated public release"))
        #expect(releaseScript.contains("INTERNAL_BETA_QUALITY_PROGRAM.md"))
        #expect(releaseScript.range(of: "exit 2")!.lowerBound < releaseScript.range(of: "ROOT_DIR=")!.lowerBound)
    }

    @Test func settingsPopupQAHonorsConfiguredAppName() throws {
        let settingsQAScript = try source("scripts/qa_settings_popups_smoke.sh")
        let commandSource = try source("Sources/MacWiki/App/MacWikiCommands.swift")
        let contentSource = try source("Sources/MacWiki/Views/ContentView.swift")
        let articleWindowSource = try source("Sources/MacWiki/Views/Shared/ArticleWindowRootView.swift")
        let advancedSettingsSource = try source("Sources/MacWiki/Views/Components/SettingsAdvancedPane.swift")
        let settingsControlsSource = try source("Sources/MacWiki/Views/Components/SettingsControls.swift")

        #expect(settingsQAScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(settingsQAScript.contains("ObjC.import('stdlib')"))
        #expect(settingsQAScript.contains("ObjC.unwrap($.getenv('APP_NAME')) || 'MacWiki'"))
        #expect(settingsQAScript.contains("ObjC.unwrap($.getenv('APP_PID'))"))
        #expect(settingsQAScript.contains("APP_NAME=\"$APP_NAME\" APP_PID=\"$QA_APP_PID\" SCRIPT_DIR=\"$SCRIPT_DIR\" qa_run_command_with_timeout 180 osascript"))
        #expect(settingsQAScript.contains("se.processes.whose({ unixId: appPid })()"))
        #expect(settingsQAScript.contains("qa_launch_exact_bundle"))
        #expect(settingsQAScript.contains("qa_assert_candidate_manifest_matches_executable \"$BUILD_INFO_PLIST\""))
        #expect(settingsQAScript.contains("qa_assert_no_conflicting_processes"))
        #expect(settingsQAScript.contains("[[ \"$VERSION\" == 1.0* ]]"))
        #expect(settingsQAScript.contains("[[ \"$TRACE_DIRTY\" == \"false\" ]]"))
        #expect(settingsQAScript.contains("function assertExactTargetFrontmost(targetWindow = null)"))
        #expect(settingsQAScript.contains("function exactKeyCode(keyCode, targetWindow = null)"))
        #expect(settingsQAScript.contains("function exactKeystroke(character, modifiers, targetWindow = null)"))
        #expect(settingsQAScript.contains("Set APP_BIN to an executable inside the exact packaged candidate."))
        #expect(settingsQAScript.contains("popups.forEach((popup, index) =>"))
        #expect(settingsQAScript.contains("expected >=2 visible popup controls"))
        #expect(settingsQAScript.contains("role === 'AXSlider'"))
        #expect(settingsQAScript.contains("expected >=6 visible native slider controls"))
        #expect(settingsQAScript.contains("is missing accessible label or value"))
        #expect(settingsQAScript.contains("verifyDestructiveCancel("))
        #expect(settingsQAScript.contains("assertDocumentCommandsUnavailableInSettings()"))
        #expect(settingsQAScript.contains("'New Reading List'"))
        #expect(settingsQAScript.contains("'New Folder'"))
        #expect(settingsQAScript.contains("'Next Tab'"))
        #expect(settingsQAScript.contains("'Previous Tab'"))
        #expect(settingsQAScript.contains("['Mark as Read', 'Mark as Unread']"))
        #expect(settingsQAScript.contains("exactly one disabled Mark as Read/Unread command"))
        #expect(settingsQAScript.contains("Command-W did not close the separate Settings window"))
        #expect(settingsQAScript.contains("Closing Settings also closed or replaced the main MacWiki window"))
        #expect(settingsQAScript.contains("'Clear All Article Cache?'"))
        #expect(settingsQAScript.contains("'Reset All App Data?'"))
        #expect(settingsQAScript.contains("exactKeyCode(53, settingsWindow()); // Escape must choose the safe cancel path."))
        #expect(settingsQAScript.contains("exactKeystroke('w', { using: 'command down' }, win);"))
        #expect(advancedSettingsSource.contains("AccessibleActionButton("))
        #expect(advancedSettingsSource.contains("\"Clear All Article Cache\","))
        #expect(advancedSettingsSource.contains("\"Reset All App Data\","))
        #expect(settingsControlsSource.contains("button.setAccessibilityLabel(title)"))
        #expect(settingsControlsSource.contains("button.setAccessibilityRole(.button)"))
        #expect(commandSource.contains("@Entry var macWikiCommandCapabilities: MacWikiCommandCapabilities?"))
        #expect(commandSource.contains("@FocusedValue(\\.macWikiCommandCapabilities)"))
        #expect(commandSource.contains("static let mainWorkspace: Self"))
        #expect(commandSource.contains("static let articleWindow: Self = [.reader, .inspector]"))
        #expect(commandSource.contains("if supports(.tabs)"))
        #expect(contentSource.contains(".focusedSceneValue(\\.macWikiCommandCapabilities, .mainWorkspace)"))
        #expect(articleWindowSource.contains(".focusedSceneValue(\\.macWikiCommandCapabilities, .articleWindow)"))
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
        #expect(profileScript.contains("def summarize_observed_cohort(cohort_name):"))
        #expect(profileScript.contains("r[\"kind\"] == \"cold\""))
        #expect(profileScript.contains("r[\"mode\"] == \"warm\" and r[\"kind\"] != \"cold\""))
        #expect(!profileScript.contains("pkill -x"))
        #expect(!profileScript.contains("APP_BINARY=\"$REPO_ROOT/.build/debug/MacWiki\""))
    }

    @Test func corruptSessionHarnessUsesIsolatedStateAndExactCandidateIdentity() throws {
        let script = try source("scripts/qa_corrupt_session_recovery.sh")

        #expect(script.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
        #expect(script.contains("qa_prepare_isolated_home"))
        #expect(script.contains("qa_assert_no_conflicting_processes"))
        #expect(script.contains("qa_launch_candidate \"$FIRST_LOG\""))
        #expect(script.contains("qa_launch_candidate \"$SECOND_LOG\""))
        #expect(script.contains("processes.whose({ unixId: appPid })()"))
        #expect(script.contains("app-state.corrupted.json"))
        #expect(script.contains("tab-session.corrupted.json"))
        #expect(script.contains("APP_SENTINEL"))
        #expect(script.contains("TAB_SENTINEL"))
        #expect(!script.contains("defaults delete com.tombunting.MacWiki"))
        #expect(!script.contains("killall"))
    }

    @Test func aboutHarnessVerifiesRenderedAndPackagedProvenance() throws {
        let script = try source("scripts/qa_about_provenance.sh")

        #expect(script.contains("CFBundleShortVersionString"))
        #expect(script.contains("CFBundleVersion"))
        #expect(script.contains("BuildInfo.plist"))
        #expect(script.contains("[[ \"$VERSION\" == 1.0* ]]"))
        #expect(script.contains("[[ \"$TRACE_DIRTY\" == \"false\" ]]"))
        #expect(script.contains("processes.whose({ unixId: appPid })()"))
        #expect(script.contains("menuItems.byName('About MacWiki').click()"))
        #expect(script.contains("qa_launch_candidate \"$APP_LOG\""))
        #expect(!script.contains("se.processes.byName"))

        let axDriver = try source("scripts/ax_about_snapshot.swift")
        #expect(axDriver.contains("AXUIElementCreateApplication(pid)"))
        #expect(axDriver.contains("kAXDialogSubrole"))
        #expect(axDriver.contains("A native macOS Wikipedia client."))
        #expect(axDriver.contains("GitHub Repository"))
        #expect(axDriver.contains("Apache-2.0"))
        #expect(axDriver.contains("MacWiki Trademark"))
    }

    @Test func readerOfflineHarnessIsTrustedIsolatedAndRetryable() throws {
        let harness = try source("scripts/qa_reader_offline_retry.sh")
        let driver = try source("scripts/ax_reader_offline_retry.swift")
        let safety = try source("scripts/lib/qa_process_safety.sh")

        #expect(harness.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
        #expect(harness.contains("export MACWIKI_QA_NETWORK_MODE=offline"))
        #expect(harness.contains("qa_launch_candidate \"$APP_LOG\""))
        #expect(harness.contains("qa_run_command_with_timeout 40 swift"))
        #expect(harness.contains("kill -0 \"$QA_APP_PID\""))
        #expect(!harness.contains("defaults delete com.tombunting.MacWiki"))
        #expect(!harness.contains("killall"))

        #expect(driver.contains("AXUIElementCreateApplication(pid)"))
        #expect(driver.contains("Failed to Load Article"))
        #expect(driver.contains("Try Again"))
        #expect(driver.contains("AXUIElementPerformAction(button, kAXPressAction"))

        #expect(safety.contains("qa_assert_supported_network_mode"))
        #expect(safety.contains("MACWIKI_QA_NETWORK_MODE=$MACWIKI_QA_NETWORK_MODE"))
        #expect(safety.contains("Refusing unsupported QA network mode"))
    }

    @Test func discoverFailureSurfaceOffersNativeRetry() throws {
        let surface = try source("Sources/MacWiki/Views/Home/Discover/DiscoverFeedSurface.swift")
        let stage = try source("Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineStageView.swift")

        #expect(surface.contains("let onRetry: () -> Void"))
        #expect(surface.contains("Button(\"Try Again\", systemImage: \"arrow.clockwise\", action: onRetry)"))
        #expect(surface.contains(".keyboardShortcut(.defaultAction)"))
        #expect(stage.contains("onRetry: screenModel.refreshDiscover"))
    }

    @Test func discoverOfflineHarnessUsesExactNativeSelectionAndRetry() throws {
        let harness = try source("scripts/qa_discover_offline_retry.sh")
        let selector = try source("scripts/ax_select_sidebar_root.swift")

        #expect(harness.contains("export MACWIKI_QA_NETWORK_MODE=offline"))
        #expect(harness.contains("discoverOpenMode -string \"Reader Page\""))
        #expect(harness.contains("ax_select_sidebar_root.swift"))
        #expect(harness.contains("\"$QA_APP_PID\" Discover"))
        #expect(harness.contains("\"Discover feed unavailable\""))
        #expect(harness.contains("kill -0 \"$QA_APP_PID\""))
        #expect(!harness.contains("killall"))

        #expect(selector.contains("AXUIElementCreateApplication(pid)"))
        #expect(selector.contains("role == (kAXButtonRole as String)"))
        #expect(selector.contains("AXUIElementPerformAction(target, kAXPressAction"))
    }

    @Test func sidebarSearchFailureOffersNativeRetry() throws {
        let content = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchContentView.swift")
        let state = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchStateView.swift")
        let surface = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")
        let coordinator = try source("Sources/MacWiki/Views/Shared/SearchCoordinator.swift")

        #expect(content.contains("actionTitle: \"Try Again\""))
        #expect(content.contains("action: onRetry"))
        #expect(state.contains("Button(actionTitle, systemImage: \"arrow.clockwise\", action: action)"))
        #expect(state.contains(".keyboardShortcut(.defaultAction)"))
        #expect(surface.contains("onRetry: model.searchCoordinator.retrySearch"))
        #expect(coordinator.contains("func retrySearch()"))
        #expect(coordinator.contains("guard hasQuery, !isLoading else { return }"))
    }

    @Test func searchOfflineHarnessUsesTrustedLaunchOverridesAndNativeRetry() throws {
        let harness = try source("scripts/qa_search_offline_retry.sh")

        #expect(harness.contains("qa.sidebarSearch.openOnLaunch -bool true"))
        #expect(harness.contains("qa.sidebarSearch.queryOnLaunch -string \"$QUERY\""))
        #expect(harness.contains("export MACWIKI_QA_NETWORK_MODE=offline"))
        #expect(harness.contains("\"$QA_APP_PID\" \"Search Unavailable\""))
        #expect(harness.contains("kill -0 \"$QA_APP_PID\""))
        #expect(!harness.contains("killall"))
        #expect(!harness.contains("defaults write com.tombunting.MacWiki"))
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
        #expect(captureScript.contains("/^[0-9]+,-?[0-9]+,-?[0-9]+,[0-9]+,[0-9]+$/"))
        #expect(captureScript.contains("hasOccludingLayerZeroWindow"))
        #expect(captureScript.contains("Refusing rectangle capture because another layer-zero window overlaps the exact PID target"))
        #expect(captureScript.contains("run_screencapture_with_timeout -x -R\"$window_x,$window_y,$window_width,$window_height\""))
        #expect(captureScript.contains("elapsed_ticks >= 15"))
        #expect(captureScript.contains("mkdir -p /tmp/macwiki-audit"))
        #expect(!captureScript.contains("pgrep -x"))

        #expect(captureSetScript.contains("APP_NAME=\"${APP_NAME:-MacWiki}\""))
        #expect(captureSetScript.contains("APP_BIN=\"${APP_BIN:-$app_binary_default}\""))
        #expect(captureSetScript.contains("APP_PID=\"$QA_APP_PID\" \"$capture_window_script\""))
        #expect(captureSetScript.contains("qa_launch_candidate"))
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
        #expect(discoverScript.contains("verify_discover_via_accessibility()"))
        #expect(discoverScript.contains("DISCOVER_VISIBLE=${discoverVisible}"))
        #expect(discoverScript.contains("TIME_MACHINE_VISIBLE=${timeMachineVisible}"))
        #expect(discoverScript.contains("defaults write \"${QA_DEFAULTS_SUITE:?}\" discoverOpenMode"))
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
            #expect(script.contains("qa_launch_exact_bundle"))
            #expect(!script.contains("pkill -x"))
            #expect(!script.contains("WORKDIR=\"/Users/tombunting/Developer/MacWiki\""))
            #expect(!script.contains("APP_BIN=\"${APP_BIN:-$WORKDIR/.build/debug/MacWiki}\""))
        }

        let sidebarCenters = try source("scripts/lib/qa_sidebar_row_centers.js")
        let folderVerifier = try source("scripts/lib/qa_verify_folder_collapse.js")
        let areaCenters = try source("scripts/lib/qa_area_row_centers.js")
        let areaRenamer = try source("scripts/lib/qa_rename_area.js")

        #expect(folderCollapseScript.contains("qa_sidebar_row_centers.js"))
        #expect(folderCollapseScript.contains("qa_verify_folder_collapse.js"))
        #expect(sidebarCenters.contains("sidebar-row-list-"))
        #expect(folderVerifier.contains("Selection did not fall back to Recents after folder collapse"))

        #expect(nestedRenameScript.contains("qa_area_row_centers.js"))
        #expect(nestedRenameScript.contains("qa_rename_area.js"))
        #expect(nestedRenameScript.contains("sidebar-row-area-"))
        #expect(!nestedRenameScript.contains("cg_right_click.swift"))
        #expect(!nestedRenameScript.contains("findRowByIdentifier"))
        #expect(!nestedRenameScript.contains("${1,,}"))
        #expect(areaCenters.contains("rowContainsIdentifier"))
        #expect(areaRenamer.contains("AXShowMenu"))
        #expect(areaRenamer.contains("AXMenuItem"))
    }

    @Test func mutatingQAHarnessesRequireIsolatedStateAndExactProcessIdentity() throws {
        let safetyLibrary = try source("scripts/lib/qa_process_safety.sh")
        let appSource = try source("Sources/MacWiki/App/MacWikiApp.swift")
        let scriptNames = [
            "scripts/profile_reader_open.sh",
            "scripts/qa_context_menu_accessibility.sh",
            "scripts/qa_context_menu_ocr.sh",
            "scripts/qa_accessibility_personalization.sh",
            "scripts/qa_folder_collapse_selected_list.sh",
            "scripts/qa_highlight_mutation.sh",
            "scripts/qa_highlight_selection_rehydrate.sh",
            "scripts/qa_label_tag_mutation.sh",
            "scripts/qa_menu_window_states.sh",
            "scripts/qa_nested_folder_rename.sh",
            "scripts/qa_organization_accessibility.sh",
            "scripts/qa_pseudolocalization.sh",
            "scripts/qa_reader_inspector_journey.sh",
            "scripts/qa_discover_scroll_time_machine.sh",
            "scripts/qa_sidebar_search_width_classes.sh",
            "scripts/qa_settings_popups_smoke.sh",
            "scripts/qa_tab_navigation_performance.sh",
            "scripts/qa_tab_reorder.sh",
            "scripts/capture_macwiki_audit_set.sh"
        ]

        #expect(safetyLibrary.contains("\"HOME=$QA_HOME\""))
        #expect(safetyLibrary.contains("\"CFFIXED_USER_HOME=$QA_HOME\""))
        #expect(safetyLibrary.contains("\"MACWIKI_QA_DEFAULTS_SUITE=${QA_DEFAULTS_SUITE:?}\""))
        #expect(safetyLibrary.contains("com.tombunting.MacWiki.qa."))
        #expect(safetyLibrary.contains("Refusing untrusted QA defaults suite"))
        #expect(safetyLibrary.contains("/usr/bin/defaults delete \"$suite_name\""))
        #expect(safetyLibrary.contains("rm -f \"$HOME/Library/Preferences/$suite_name.plist\""))
        #expect(safetyLibrary.contains("qa_launch_exact_bundle()"))
        #expect(safetyLibrary.contains("qa_launch_candidate()"))
        #expect(safetyLibrary.contains("qa_run_command_with_timeout()"))
        #expect(safetyLibrary.contains("if [[ -t 0 ]]; then"))
        #expect(safetyLibrary.contains(": >\"$input_path\""))
        #expect(safetyLibrary.contains("cat >\"$input_path\""))
        #expect(safetyLibrary.contains("\"$@\" <\"$input_path\" &"))
        #expect(safetyLibrary.contains("--env \"HOME=$QA_HOME\""))
        #expect(safetyLibrary.contains("--env \"CFFIXED_USER_HOME=$QA_HOME\""))
        #expect(safetyLibrary.contains("--env \"MACWIKI_QA_DEFAULTS_SUITE=${QA_DEFAULTS_SUITE:?}\""))
        #expect(!safetyLibrary.contains("MACWIKI_QA_BACKGROUND_LAUNCH"))
        #expect(!safetyLibrary.contains("open_arguments+=(-g)"))
        #expect(!appSource.contains("MACWIKI_QA_BACKGROUND_LAUNCH"))
        #expect(!appSource.contains("window.orderBack(nil)"))
        #expect(safetyLibrary.contains("MACWIKI_QA_ACCESSIBILITY_PROFILE=$MACWIKI_QA_ACCESSIBILITY_PROFILE"))
        #expect(safetyLibrary.contains("qa_assert_supported_pseudolocalization"))
        #expect(safetyLibrary.contains("-NSDoubleLocalizedStrings YES"))
        #expect(!safetyLibrary.contains("local launch_arguments=()"))
        #expect(safetyLibrary.contains("qa_pid_executable_path"))
        #expect(safetyLibrary.contains("/usr/sbin/lsof -a -p \"$pid\" -d txt -Fn"))
        #expect(safetyLibrary.contains("Refusing to run while $APP_NAME PID"))

        for scriptName in scriptNames {
            let script = try source(scriptName)
            #expect(script.contains("qa_process_safety.sh"))
            #expect(!script.contains("pkill -x"))
            #expect(!script.contains("open -n \"$APP_BIN\""))
            #expect(!script.contains("$HOME/Library/Application Support/default.store"))
        }

        let personalizationHarness = try source("scripts/qa_accessibility_personalization.sh")
        #expect(personalizationHarness.contains("MACWIKI_QA_ACCESSIBILITY_PROFILE"))
        #expect(personalizationHarness.contains("ax_accessibility_personalization.swift"))
        #expect(personalizationHarness.contains("capture_macwiki_window.sh"))
        #expect(personalizationHarness.contains("compare_images.swift"))
        #expect(personalizationHarness.contains("visual-diff.json"))
        #expect(personalizationHarness.contains("Production preferences/data or global accessibility settings touched"))

        let pseudolocalizationHarness = try source("scripts/qa_pseudolocalization.sh")
        #expect(pseudolocalizationHarness.contains("MACWIKI_QA_PSEUDOLOCALIZATION=1"))
        #expect(pseudolocalizationHarness.contains("Welcome to MacWiki Welcome to MacWiki"))
        #expect(pseudolocalizationHarness.contains("STRICT_OCR=1"))
        #expect(pseudolocalizationHarness.contains("Production preferences/data or global language settings touched"))

        let captureHarness = try source("scripts/capture_macwiki_window.sh")
        #expect(captureHarness.contains("pwd -P"))
        #expect(captureHarness.contains("actual_binary=\"$(cd \"$(dirname \"$actual_binary\")\""))

        let discoverScript = try source("scripts/qa_discover_scroll_time_machine.sh")
        let launchRange = try #require(discoverScript.range(of: "qa_launch_candidate \"/tmp/macwiki-qa-discover-launch.log\""))
        let boundsRange = try #require(discoverScript.range(of: "window_info=\"$(ensure_macwiki_window)\""))
        #expect(launchRange.lowerBound < boundsRange.lowerBound)
        #expect(!discoverScript.contains("--flip-y"))
        #expect(discoverScript.contains("if [[ \"$qa_status\" != \"PASS\" ]]"))
        #expect(discoverScript.contains("did not reach and verify both Discover and Time Machine UI"))
        let folderCollapseScript = try source("scripts/qa_folder_collapse_selected_list.sh")
        let nestedRenameScript = try source("scripts/qa_nested_folder_rename.sh")
        #expect(!folderCollapseScript.contains("--flip-y"))
        #expect(!nestedRenameScript.contains("--flip-y"))
    }

    @Test func menuContextAndOrganizationHarnessesKeepReportsNonExecutableAndStateIsolated() throws {
        let menuHarness = try source("scripts/qa_menu_window_states.sh")
        let contextHarness = try source("scripts/qa_context_menu_accessibility.sh")
        let organizationHarness = try source("scripts/qa_organization_accessibility.sh")
        let highlightHarness = try source("scripts/qa_highlight_mutation.sh")
        let highlightDriver = try source("scripts/ax_highlight_mutation.swift")
        let highlightSelectionHarness = try source("scripts/qa_highlight_selection_rehydrate.sh")
        let highlightSelectionDriver = try source("scripts/ax_highlight_selection_rehydrate.swift")
        let labelTagHarness = try source("scripts/qa_label_tag_mutation.sh")

        for harness in [menuHarness, contextHarness, organizationHarness, highlightHarness, highlightSelectionHarness, labelTagHarness] {
            #expect(harness.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
            #expect(harness.contains("qa_prepare_isolated_home"))
            #expect(harness.contains("qa_assert_no_conflicting_processes"))
            #expect(harness.contains("qa_launch_candidate \"$APP_LOG\""))
            #expect(harness.contains("APP_PID=\"$QA_APP_PID\""))
            #expect(harness.contains("[[ \"$VERSION\" == 1.0* ]]"))
            #expect(harness.contains("[[ \"$TRACE_DIRTY\" == \"false\" ]]"))
            #expect(harness.contains("printf -- '- Candidate binary: `%s`\\n' \"$APP_BIN\""))
            #expect(!harness.contains("<<REPORT"))
            #expect(!harness.contains("pkill -x"))
        }

        #expect(menuHarness.contains("processes.whose({ unixId: pid })"))
        #expect(menuHarness.contains("['Article', 'Back']"))
        #expect(menuHarness.contains("enabled('Tabs', 'Next Tab')"))
        #expect(menuHarness.contains("['View', 'Increase Reader Font Size'"))
        #expect(menuHarness.contains("Window did not enter native full screen"))
        #expect(menuHarness.contains("MacWiki did not enter an inactive application state"))
        #expect(contextHarness.contains("qa_assert_isolated_path \"$STORE_PATH\" \"$QA_HOME\""))
        #expect(contextHarness.contains("sidebar-row-area-$FOLDER_ID"))
        #expect(contextHarness.contains("sidebar-row-list-$LIST_ID"))
        #expect(organizationHarness.contains("'New List or Folder', 'New Label', 'New Tag'"))
        #expect(organizationHarness.contains("waitForNamed('Choose list icon')"))
        #expect(organizationHarness.contains("waitForNamed('Choose folder icon')"))
        #expect(organizationHarness.contains("waitForNamed('Choose label color')"))
        #expect(organizationHarness.contains("'Red', 'Orange', 'Yellow', 'Green', 'Blue', 'Purple', 'Pink', 'Gray'"))
        #expect(organizationHarness.contains("observations.tagSheet.createEnabled === false"))
        #expect(contextHarness.contains("AXShowMenu"))
        #expect(highlightHarness.contains("qa.fixture.highlight.articleTitle"))
        #expect(highlightHarness.contains("qa.fixture.highlight.text"))
        #expect(highlightHarness.contains("qa_assert_isolated_path \"$STORE_PATH\" \"$QA_HOME\""))
        #expect(highlightHarness.contains("swift \"$SCRIPT_DIR/ax_highlight_mutation.swift\""))
        #expect(highlightHarness.contains("Delete Highlight"))
        #expect(highlightHarness.contains("SELECT count(*) FROM ZHIGHLIGHT"))
        #expect(highlightDriver.contains("guard role(of: element) != \"AXWebArea\""))
        #expect(highlightDriver.contains("kAXShowMenuAction"))
        #expect(highlightDriver.contains("named: \"Blue\""))
        #expect(highlightDriver.contains("named: \"Delete Highlight\""))
        #expect(highlightSelectionHarness.contains("qa_assert_isolated_path \"$STORE_PATH\" \"$QA_HOME\""))
        #expect(highlightSelectionHarness.contains("ax_highlight_selection_rehydrate.swift\" create"))
        #expect(highlightSelectionHarness.contains("ax_highlight_selection_rehydrate.swift\" rehydrate"))
        #expect(highlightSelectionHarness.contains("ZELEMENTPATH AS elementPath"))
        #expect(highlightSelectionHarness.contains("ZISSTALERAW=0 AND ZISARCHIVEDRAW=0"))
        #expect(highlightSelectionHarness.contains(": >\"$APP_LOG\""))
        #expect(highlightSelectionHarness.contains(": >\"$RELAUNCH_LOG\""))
        #expect(highlightSelectionHarness.contains("AttributeGraph cycles"))
        #expect(highlightSelectionDriver.contains("kAXStringForRangeParameterizedAttribute"))
        #expect(highlightSelectionDriver.contains("kAXBoundsForRangeParameterizedAttribute"))
        #expect(highlightSelectionDriver.contains("kAXSelectedTextMarkerRangeAttribute"))
        #expect(highlightSelectionDriver.contains("named: \"Highlight Color\""))
        #expect(labelTagHarness.contains("createRenameDelete('New Label'"))
        #expect(labelTagHarness.contains("createRenameDelete('New Tag'"))
        #expect(labelTagHarness.contains("SELECT count(*) FROM ZLABEL"))
        #expect(labelTagHarness.contains("SELECT count(*) FROM ZTAG"))
    }

    @Test func unquotedShellHeredocsCannotExecuteMarkdownBackticks() throws {
        let scriptsDirectory = repositoryRoot().appendingPathComponent("scripts")
        let scripts = try FileManager.default.contentsOfDirectory(
            at: scriptsDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "sh" }
        let opener = try NSRegularExpression(pattern: #"<<-?\s*([A-Za-z_][A-Za-z0-9_]*)"#)

        func containsUnescapedBacktick(_ line: String) -> Bool {
            for index in line.indices where line[index] == "`" {
                var slashCount = 0
                var cursor = index
                while cursor > line.startIndex {
                    cursor = line.index(before: cursor)
                    guard line[cursor] == "\\" else { break }
                    slashCount += 1
                }
                if slashCount.isMultiple(of: 2) { return true }
            }
            return false
        }

        for scriptURL in scripts.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let lines = try String(contentsOf: scriptURL, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map(String.init)
            var unquotedDelimiter: String?

            for (offset, line) in lines.enumerated() {
                if let delimiter = unquotedDelimiter {
                    if line.trimmingCharacters(in: .whitespaces) == delimiter {
                        unquotedDelimiter = nil
                    } else if containsUnescapedBacktick(line) {
                        Issue.record(
                            "Unescaped backtick in unquoted heredoc at \(scriptURL.lastPathComponent):\(offset + 1)"
                        )
                    }
                    continue
                }

                let range = NSRange(line.startIndex..<line.endIndex, in: line)
                guard let match = opener.firstMatch(in: line, range: range),
                      let delimiterRange = Range(match.range(at: 1), in: line) else {
                    continue
                }
                unquotedDelimiter = String(line[delimiterRange])
            }
        }
    }

    @Test func readerInspectorHarnessUsesExactPackagedStateAndNativeAXActions() throws {
        let harness = try source("scripts/qa_reader_inspector_journey.sh")
        let driver = try source("scripts/ax_reader_inspector_journey.swift")

        #expect(harness.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
        #expect(harness.contains("STATE_DIR=\"$QA_HOME/Library/Application Support/MacWiki\""))
        #expect(harness.contains("qa_prepare_isolated_home"))
        #expect(harness.contains("qa_assert_candidate_manifest_matches_executable"))
        #expect(harness.contains("qa_assert_no_conflicting_processes"))
        #expect(harness.contains("rm -f \"$APP_LOG\" \"$AX_RESULT\" \"$REPORT_PATH\""))
        #expect(harness.contains("qa_launch_candidate \"$APP_LOG\""))
        #expect(harness.contains("[[ \"$VERSION\" == 1.0* ]]"))
        #expect(harness.contains("swiftc \"$SCRIPT_DIR/ax_reader_inspector_journey.swift\" -o \"$AX_DRIVER_BIN\""))
        #expect(harness.contains("if ! MACWIKI_QA_APP_LOG=\"$APP_LOG\" qa_run_command_with_timeout 90 \"$AX_DRIVER_BIN\""))
        #expect(harness.contains("\"$QA_APP_PID\" \"$ARTICLE_TITLE\""))
        #expect(harness.contains("READER_PID=\"$QA_APP_PID\""))
        #expect(harness.contains("Exact candidate PID: `%s`\\n' \"$READER_PID\""))
        #expect(harness.contains("12 rapid pane cycles"))
        #expect(harness.contains("Isolated QA home"))
        #expect(harness.contains("fatal error|precondition failed|assertion failed"))
        #expect(harness.contains("AttributeGraph: cycle detected"))

        #expect(driver.contains("AXUIElementCreateApplication(pid)"))
        #expect(driver.contains("kAXPressAction"))
        #expect(driver.contains("kAXRadioButtonRole"))
        #expect(driver.contains("kAXToolbarRole"))
        #expect(driver.contains("kAXMenuButtonRole"))
        #expect(driver.contains("for cycle in 1...12"))
        #expect(driver.contains("No Highlights Yet"))
        #expect(driver.contains("No References Found"))
        #expect(driver.contains("Populated reference list"))
        #expect(driver.contains("Find in page"))
        #expect(driver.contains("Hide List Contents"))
        #expect(driver.contains("Page Views"))
        #expect(driver.contains("Open in Browser"))
        #expect(driver.contains("matchingElements("))
        #expect(driver.contains(".count == 1"))
        #expect(driver.contains("toolbar hidden → restored"))
        #expect(driver.contains("900-point window and visible reader preserved while both auxiliary panes restored"))
        #expect(driver.contains("Restoring panes resized the whole window"))
        #expect(driver.contains("for _ in 0..<8"))
        #expect(driver.contains("containsLabel(articleTitle, in: reader)"))
        #expect(driver.contains("settleAccessibility(for: 1.0)"))
        #expect(driver.contains("stringAttribute(kAXTitleAttribute as CFString, from: window) == \"MacWiki\""))
        #expect(driver.contains("containsLabel(articleTitle, in: reader)"))
        #expect(driver.contains("kAXFocusedUIElementAttribute"))
        #expect(driver.contains("let menuRoots = applicationChildren.filter"))
        #expect(driver.contains("private func nativeToolbar(in window:"))
        #expect(driver.contains("private func workspaceSplitGroup(in window:"))
        #expect(driver.contains("private func inspectorPane(in window:"))
        #expect(driver.contains("private func readerPane(in window:"))
        #expect(driver.contains(".filter { !hasRole($0, kAXRadioGroupRole as String) }"))
        #expect(driver.contains("let refreshed = try? inspectorButton(label)"))
        #expect(!driver.contains("elements(in: contentWindow"))
        #expect(!driver.contains("labels(in: contentWindow"))
        #expect(!driver.contains("MACWIKI_QA_AX_PAUSE_BEFORE_RESIZE"))
        #expect(!driver.contains("return element(in: application, role: kAXMenuItemRole"))
        #expect(!driver.contains("Open in Browser (More)"))
    }

    @Test func toolbarCustomizationHarnessCommitsAndVerifiesNativeOrderAcrossRelaunch() throws {
        let harness = try source("scripts/qa_toolbar_customization_journey.sh")
        let driver = try source("scripts/ax_toolbar_customization_journey.swift")

        #expect(harness.contains("source \"$SCRIPT_DIR/lib/qa_process_safety.sh\""))
        #expect(harness.contains("qa_prepare_isolated_home"))
        #expect(harness.contains("qa_assert_candidate_manifest_matches_executable"))
        #expect(harness.contains("qa_assert_no_conflicting_processes"))
        #expect(harness.contains("qa_launch_candidate \"$FIRST_LOG\""))
        #expect(harness.contains("qa_launch_candidate \"$RELAUNCH_LOG\""))
        #expect(harness.contains("verify-order"))
        #expect(harness.contains("NSToolbar Configuration main-window-reader-scoped-toolbar-v15"))
        #expect(harness.contains("AttributeGraph: cycle detected"))
        #expect(harness.contains("[[ \"$VERSION\" == 1.0* ]]"))
        #expect(harness.contains("FIRST_PID=\"$QA_APP_PID\""))
        #expect(harness.contains("RELAUNCH_PID=\"$QA_APP_PID\""))
        #expect(harness.contains("Isolated QA home"))

        #expect(driver.contains("Customize Toolbar"))
        #expect(driver.contains("kAXSheetRole"))
        #expect(driver.contains("kAXToolbarRole"))
        #expect(driver.contains("kAXImageRole"))
        #expect(driver.contains("private func drag(from start: CGPoint, to end: CGPoint)"))
        #expect(driver.contains("removed Reader Style, restored it before Page Views"))
        #expect(driver.contains("rejected a cross-boundary move"))
        #expect(driver.contains("kept Inspector fixed"))
        #expect(driver.contains("Reader Style remains before Page Views"))
        #expect(driver.contains("wait(timeout: 5"))
        #expect(driver.components(separatedBy: "try activateTarget(pid: pid, application: application, window: window)").count - 1 >= 4)
        #expect(driver.contains("The target customization sheet lost focus before the boundary probe."))
        #expect(!driver.contains("System Events"))
    }

    @Test func widthClassHarnessUsesReachableVerifiedWindowSizes() throws {
        let script = try source("scripts/qa_sidebar_search_width_classes.sh")
        let captureScript = try source("scripts/capture_macwiki_window.sh")
        let performanceDumpScript = try source("scripts/dump_performance_metrics.swift")

        #expect(script.contains("WIDTH_PRESETS_CSV=\"${WIDTH_PRESETS_CSV:-1040,1400,1760}\""))
        #expect(script.contains("performance-metrics.csv"))
        #expect(script.contains("qa_assert_candidate_manifest_matches_executable"))
        #expect(script.contains("tab-session.json"))
        #expect(script.contains("driver_status"))
        #expect(script.contains("dump_performance_metrics.swift"))
        #expect(performanceDumpScript.contains("com.tombunting.MacWiki.qa."))
        #expect(performanceDumpScript.contains("sessionRestore"))
        #expect(performanceDumpScript.contains("sidebarHydration"))
        #expect(script.contains("Verified actual window width"))
        #expect(script.contains("Could not establish and verify target window width"))
        #expect(!script.contains("236,288,360"))
        #expect(!script.contains("esc badge"))
        #expect(captureScript.contains("for attempt in 1 2 3"))
        #expect(captureScript.contains("after 3 attempts"))
    }

    @Test func internalBetaPerformanceBudgetsAreExplicitAndEnforced() throws {
        let budgets = try source("INTERNAL_BETA_PERFORMANCE_BUDGETS.json")
        let verifier = try source("scripts/verify_performance_budgets.py")
        let readerProfiler = try source("scripts/profile_reader_open.sh")

        #expect(budgets.contains("readerColdReveal"))
        #expect(budgets.contains("readerWarmReveal"))
        #expect(budgets.contains("sidebarHydration"))
        #expect(budgets.contains("tabSwitch"))
        #expect(budgets.contains("appWindowReadinessMilliseconds"))
        #expect(budgets.contains("discoverAccessibilityTraversalMilliseconds"))
        #expect(budgets.contains("must not be relaxed solely to pass a candidate"))
        #expect(verifier.contains("minimumSamples"))
        #expect(verifier.contains("measured <= maximum"))
        #expect(verifier.contains("Overall: **{'FAIL' if failures else 'PASS'}**"))
        #expect(readerProfiler.contains("qa_run_command_with_timeout \"$((trace_seconds + 30))\" xcrun xctrace record"))
        #expect(readerProfiler.contains("qa_run_command_with_timeout 90 xcrun xctrace export"))
        #expect(readerProfiler.contains("MACWIKI_QA_DEFAULTS_SUITE=$QA_DEFAULTS_SUITE"))
        #expect(readerProfiler.contains("candidate_pids=\"$(qa_exact_binary_pids)\""))
        #expect(!readerProfiler.contains("tell application (item 1 of argv) to activate"))
    }

    @Test func tabNavigationHarnessUsesNativeCommandsAndExactAXState() throws {
        let script = try source("scripts/qa_tab_navigation_performance.sh")
        let driver = try source("scripts/ax_tab_navigation.swift")

        #expect(script.contains("qa_launch_candidate"))
        #expect(script.contains("qa_run_command_with_timeout 30 swift"))
        #expect(script.contains("ax_tab_navigation.swift"))
        #expect(script.contains("performance-metrics.csv"))
        #expect(driver.contains("AXUIElementCreateApplication"))
        #expect(driver.contains("kAXValueAttribute"))
        #expect(driver.contains("value.hasPrefix(\"Active tab\")"))
        #expect(driver.contains("CGEvent(keyboardEventSource:"))
        #expect(driver.contains("DispatchTime.now().uptimeNanoseconds"))
        #expect(driver.contains("for _ in 0..<3"))
        #expect(driver.contains("NSRunningApplication(processIdentifier: processID)"))
        #expect(driver.contains("NSWorkspace.shared.frontmostApplication?.processIdentifier == processID"))
        #expect(driver.contains("kAXRaiseAction"))
        #expect(driver.contains("waitForTabBar(in: application"))
        #expect(driver.contains("description == \"New Tab\""))
    }

    @Test func tabReorderHarnessCoversLongTitleOverflowPersistenceAndCleanup() throws {
        let tabBar = try source("Sources/MacWiki/Views/Components/TabBarView.swift")
        let tabSessionStore = try source("Sources/MacWiki/App/TabSessionStore.swift")
        let tabItem = try source("Sources/MacWiki/Views/Components/ReaderTabItemView.swift")
        let tabAccessories = try source("Sources/MacWiki/Views/Components/ReaderTabAccessoryCluster.swift")
        let reorderDrag = try source("Sources/MacWiki/Views/Components/TabReorderDragModifier.swift")
        let harness = try source("scripts/qa_tab_reorder.sh")
        let driver = try source("scripts/ax_tab_reorder.swift")

        #expect(tabBar.contains("private var minimumTabsContentWidth"))
        #expect(tabBar.contains("private var tabsContentWidth: CGFloat"))
        #expect(tabBar.contains("private var tabFrames: [UUID: CGRect]"))
        #expect(tabBar.contains("minimumTabsContentWidth > (tabsViewportWidth + 1)"))
        #expect(!tabBar.contains("TabContentWidthPreferenceKey"))
        #expect(!tabBar.contains("TabFramePreferenceKey"))
        #expect(tabBar.contains(".onScrollGeometryChange(for: CGRect.self)"))
        #expect(!tabBar.contains(".reorderable()"))
        #expect(!tabBar.contains(".reorderContainer("))
        #expect(tabBar.contains("ForEach(appState.openTabs)"))
        #expect(!tabBar.contains("ForEach(Array(appState.openTabs.enumerated())"))
        #expect(!tabBar.contains(".id(tab.id)"))
        #expect(!tabBar.contains("tabMembership"))
        #expect(!tabBar.contains(".onChange(of: appState.openTabs.map(\\.id))"))
        #expect(!tabBar.contains(".scrollDisabled(draggedTabId != nil)"))
        #expect(tabBar.contains("Unexpected identifier type"))
        #expect(tabItem.contains("TabReorderDragModifier("))
        #expect(reorderDrag.contains(".highPriorityGesture("))
        #expect(tabAccessories.contains(".accessibilityLabel(\"All Tabs\")"))
        #expect(harness.contains("qa_assert_isolated_path \"$STATE_DIR\" \"$QA_HOME\""))
        #expect(harness.contains("Set APP_BIN to an exact packaged MacWiki candidate binary."))
        #expect(harness.contains("TAB_COUNT=16"))
        #expect(harness.contains("[[ \"$VERSION\" == 1.0* ]]"))
        #expect(harness.contains("[[ \"$TRACE_DIRTY\" == \"false\" ]]"))
        #expect(harness.contains("qa_assert_candidate_manifest_matches_executable \"$BUILD_INFO_PLIST\""))
        #expect(harness.contains("persisted_titles"))
        #expect(harness.contains("RELAUNCH_PID=\"$QA_APP_PID\""))
        #expect(harness.contains("verify-order \"$RESULT_JSON\""))
        #expect(harness.contains("relaunch_titles"))
        #expect(harness.contains("relaunch_overflow_count"))
        #expect(harness.contains("ATTRIBUTEGRAPH_CYCLE_COUNT"))
        #expect(harness.contains("rg -c 'AttributeGraph: cycle detected' \"$FIRST_LOG\" \"$RELAUNCH_LOG\" || true"))
        #expect(harness.contains(": >\"$FIRST_LOG\""))
        #expect(harness.contains(": >\"$RELAUNCH_LOG\""))
        #expect(harness.contains("Tab reorder journey emitted"))
        #expect(!tabBar.contains("@GestureState private var isDragActive"))
        #expect(!tabBar.contains(".updating($isDragActive)"))
        #expect(tabBar.contains("Task.sleep(for: .milliseconds(1))"))
        #expect(tabBar.contains("transaction.disablesAnimations = true"))
        #expect(tabBar.contains("withTransaction(transaction)"))
        #expect(tabBar.contains("Clear the transient drag graph first"))
        #expect(tabSessionStore.contains("var reordered = openTabs"))
        #expect(tabSessionStore.contains("openTabs = reordered"))
        #expect(!tabSessionStore.contains("let tab = openTabs.remove(at: sourceIndex)"))
        #expect(!tabBar.contains(".animation(interactionProfile.neighborShift, value: shiftAmount)"))
        #expect(!tabBar.contains(".animation(interactionProfile.dragLift, value: isDragged)"))
        #expect(tabAccessories.components(separatedBy: ".accessibilityLabel(\"All Tabs\")").count >= 3)
        #expect(driver.contains("The constrained tab lane did not expose All Tabs overflow."))
        #expect(driver.contains("MACWIKI_QA_TAB_DRAG_PROBE"))
        #expect(driver.contains("Same-slot probe unexpectedly changed tab order."))
        #expect(driver.contains("mode: sameSlotProbe ? \"same-slot\""))
        #expect(driver.contains("Tab drag did not publish a reordered accessibility sequence."))
        #expect(driver.contains("NSRunningApplication(processIdentifier: pid)"))
        #expect(driver.contains("NSWorkspace.shared.frontmostApplication?.processIdentifier == pid"))
        #expect(driver.contains("let originalPointer = CGEvent(source: nil)?.location"))
        #expect(driver.contains("if isLeftMouseDown"))
        #expect(driver.contains("verify-order"))
    }

    @Test func readerObservesNarrowStoredTabStateInsteadOfOrderedTabs() throws {
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let appState = try source("Sources/MacWiki/App/AppState.swift")
        let tabSessionStore = try source("Sources/MacWiki/App/TabSessionStore.swift")
        let projectionTests = try source("Tests/MacWikiTests/ActiveReaderProjectionTests.swift")

        #expect(reader.contains("let readerProjection = appState.activeReaderProjection"))
        #expect(reader.contains(".onChange(of: appState.openTabIDs)"))
        #expect(!reader.contains("appState.openTabs"))
        #expect(appState.contains("var activeReaderProjection: ActiveReaderProjection"))
        #expect(appState.contains("var openTabIDs: Set<UUID>"))
        #expect(tabSessionStore.contains("private(set) var activeReaderProjection: ActiveReaderProjection = .empty"))
        #expect(tabSessionStore.contains("private(set) var openTabIDs: Set<UUID> = []"))
        #expect(tabSessionStore.contains("guard updatedProjection != activeReaderProjection else { return }"))
        #expect(tabSessionStore.contains("guard updatedIDs != openTabIDs else { return }"))
        #expect(projectionTests.contains("pureReorderDoesNotPublishReaderProjectionOrMembership"))
        #expect(projectionTests.contains("#expect(invalidations.value == 0)"))
    }

    @Test func sidebarSearchOwnsItsNativeTopSafeArea() throws {
        let source = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")

        #expect(source.contains(".safeAreaPadding(.top)"))
        #expect(source.contains(".padding(.top, ReaderTabLaneMetrics.height)"))
        #expect(!source.contains("topObscuredHeight"))
    }

    @Test func mainWindowShellKeepsAStableNativeSplitHierarchyAndUsesKeyPathBindings() throws {
        let shellSource = try source("Sources/MacWiki/Views/Shared/MainWindowShell.swift")
        let nativeSplit = try source("Sources/MacWiki/Views/Shared/NativeWorkspaceSplitView.swift")
        let splitController = try source("Sources/MacWiki/Views/Shared/WorkspaceSplitViewController.swift")

        #expect(shellSource.contains("private struct MainWorkspaceShell: View"))
        #expect(!shellSource.contains("NavigationSplitView"))
        #expect(shellSource.contains("NativeWorkspaceSplitView("))
        #expect(!shellSource.contains("private struct MainSidebarReaderShell: View"))
        #expect(!shellSource.contains("private struct MainReaderOnlyShell: View"))
        #expect(shellSource.contains("inspectorVisible: $appState.inspectorVisible"))
        #expect(shellSource.contains("InspectorColumnView()"))
        #expect(!shellSource.contains(".inspector(isPresented:"))
        #expect(!shellSource.contains("Binding(\n"))
        #expect(nativeSplit.contains("receiveNativeVisibility"))
        #expect(splitController.contains("final class WorkspaceSplitViewController: NSSplitViewController"))
        #expect(splitController.contains("NSSplitViewItem(sidebarWithViewController:"))
        #expect(splitController.contains("NSSplitViewItem(contentListWithViewController:"))
        #expect(splitController.contains("NSSplitViewItem(viewController: readerController)"))
        #expect(splitController.contains("NSSplitViewItem(inspectorWithViewController:"))
        #expect(splitController.contains("addSplitViewItem(sidebarItem)"))
        #expect(splitController.contains("addSplitViewItem(directoryItem)"))
        #expect(splitController.contains("addSplitViewItem(readerItem)"))
        #expect(splitController.contains("addSplitViewItem(inspectorItem)"))
        #expect(splitController.contains("allowsFullHeightLayout = true"))
        #expect(splitController.contains("canCollapse: true"))
        #expect(splitController.contains("canCollapse: false"))
        #expect(splitController.contains("override func splitViewDidResizeSubviews"))
        #expect(splitController.contains("splitView.setPosition(initialSidebarWidth"))
        #expect(splitController.contains("directoryItem.viewController.view.convert("))
        #expect(splitController.contains("directoryLeadingEdge + initialDirectoryWidth"))
        #expect(splitController.contains("splitView.setPosition(splitWidth - initialInspectorWidth"))
        #expect(splitController.contains("preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension"))
        #expect(splitController.contains("automaticMaximumThickness = NSSplitViewItem.unspecifiedDimension"))
        #expect(splitController.contains("AppStorageKey.MainWindow.sidebarWidth"))
        #expect(splitController.contains("AppStorageKey.MainWindow.directoryWidth"))
        #expect(splitController.contains("AppStorageKey.MainWindow.inspectorWidth"))
        #expect(!splitController.contains("autosaveName"))
        let directoryColumn = try source("Sources/MacWiki/Views/Columns/DirectoryColumnView.swift")
        #expect(!directoryColumn.contains("AppStorageKey.MainWindow.directoryWidth"))
        let listsColumn = try source("Sources/MacWiki/Views/Columns/ListsColumnView.swift")
        #expect(!listsColumn.contains("navigationSplitViewColumnWidth"))
        #expect(!listsColumn.contains("persistedColumnWidth"))
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

        #expect(source.contains("List {"))
        #expect(source.contains("ForEach(presentedLists)"))
        #expect(source.contains("ReadingListPresentationOrder"))
        #expect(source.contains(".toggleStyle(.checkbox)"))
        #expect(source.contains("ContentUnavailableView"))
        #expect(source.contains("ArticleLibraryActions.saveToList"))
        #expect(source.contains("ArticleLibraryActions.removeAllFromList"))
        #expect(source.contains("min(max(CGFloat(presentedLists.count) * 34, 112), 280)"))
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
