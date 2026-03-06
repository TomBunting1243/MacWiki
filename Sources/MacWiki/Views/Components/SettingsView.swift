import SwiftUI
import Foundation
import SwiftData

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("labelDisplayMode") private var labelDisplayMode: LabelDisplayMode = .rowHighlight
    @AppStorage("highlightMarkerStyle") private var highlightMarkerStyle: HighlightMarkerStyle = .dot
    @AppStorage("highlightHeaderWrap") private var highlightHeaderWrap = false
    @AppStorage("nativeHighlightingMenuEnabled") private var nativeHighlightingMenuEnabled = false
    @AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = .system
    @AppStorage(ReaderAppearanceStorageKey.fontSize) private var readerFontSize: Double = ReaderAppearance.default.fontSize
    @AppStorage(ReaderAppearanceStorageKey.lineHeight) private var readerLineHeight: Double = ReaderAppearance.default.lineHeight
    @AppStorage(ReaderAppearanceStorageKey.paragraphSpacing) private var readerParagraphSpacing: Double = ReaderAppearance.default.paragraphSpacing
    @AppStorage(ReaderAppearanceStorageKey.contentWidth) private var readerContentWidth: Double = ReaderAppearance.default.contentWidth
    @AppStorage(ReaderAppearanceStorageKey.horizontalPadding) private var readerHorizontalPadding: Double = ReaderAppearance.default.horizontalPadding
    @AppStorage(ReaderAppearanceStorageKey.headingScale) private var readerHeadingScale: Double = ReaderAppearance.default.headingScale
    @AppStorage("discoverOpenMode") private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage("searchPresentationMode") private var searchPresentationMode: SearchPresentationMode = .overlay
    @AppStorage("recentsScope") private var recentsScope: RecentsScope = .currentTab
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @AppStorage(TabAccompanimentStorageKey.showSavedMarker) private var showSavedTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showHighlightMarker) private var showHighlightTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showReadMarker) private var showReadTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showProgressTrack) private var showTabProgressTrack = true
    @AppStorage(TabAccompanimentStorageKey.showActiveDepth) private var showTabActiveDepth = true
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage("features.wikiHopPostV1Enabled") private var wikiHopPostV1Enabled = false
    @State private var cacheMetrics: WikipediaService.CacheMetrics?
    @State private var performanceMetrics = PerformanceMetricsStore.shared
    @State private var isCacheActionRunning = false
    @State private var cacheStatusMessage: String?
    @State private var pendingCacheAction: CacheAction?
    @State private var showReaderFineTuning = false
    @State private var selectedSettingsSection: SettingsSection? = .reading
    @State private var selectedAdvancedPanel: AdvancedPanel = .chrome

    private static let cacheByteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }()

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }

    private enum CacheAction: String, Identifiable {
        case clearMemory
        case clearTemporaryDisk
        case clearAllArticleCache
        case resetAllAppData

        var id: String { rawValue }

        var requiresConfirmation: Bool {
            switch self {
            case .clearMemory:
                return false
            case .clearTemporaryDisk, .clearAllArticleCache, .resetAllAppData:
                return true
            }
        }

        var confirmationTitle: String {
            switch self {
            case .clearMemory:
                return "Clear Memory Cache?"
            case .clearTemporaryDisk:
                return "Clear Temporary Disk Cache?"
            case .clearAllArticleCache:
                return "Clear All Article Cache?"
            case .resetAllAppData:
                return "Reset All App Data?"
            }
        }

        var confirmationMessage: String {
            switch self {
            case .clearMemory:
                return "This removes in-memory article cache for the current app session."
            case .clearTemporaryDisk:
                return "This removes non-pinned disk-cached articles. Saved, highlighted, and tagged articles remain cached."
            case .clearAllArticleCache:
                return "This removes all article cache data, including pinned saved/highlighted/tagged entries."
            case .resetAllAppData:
                return "This removes all local data: lists, saved articles, highlights, notes, labels, tags, reading progress, tabs, cache, and preferences. This action cannot be undone."
            }
        }

        var successMessage: String {
            switch self {
            case .clearMemory:
                return "Memory cache cleared."
            case .clearTemporaryDisk:
                return "Temporary disk cache cleared. Pinned article cache was preserved."
            case .clearAllArticleCache:
                return "All article cache was cleared."
            case .resetAllAppData:
                return "All local app data was reset."
            }
        }

        var confirmationButtonLabel: String {
            switch self {
            case .resetAllAppData:
                return "Reset"
            default:
                return "Clear"
            }
        }
    }

    private enum AdvancedPanel: String, CaseIterable, Identifiable {
        case chrome
        case experiments
        case storage

        var id: String { rawValue }

        var title: String {
            switch self {
            case .chrome:
                return "Chrome"
            case .experiments:
                return "Experiments"
            case .storage:
                return "Storage"
            }
        }

        var subtitle: String {
            switch self {
            case .chrome:
                return "Discover defaults, tab markers, and toolbar guidance."
            case .experiments:
                return "Feature flags that may change or disappear."
            case .storage:
                return "Cache controls and full local reset actions."
            }
        }
    }

    private enum SettingsSection: String, CaseIterable, Identifiable {
        case reading
        case highlights
        case navigation
        case advanced

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reading:
                return "Reading"
            case .highlights:
                return "Highlights"
            case .navigation:
                return "Navigation"
            case .advanced:
                return "Advanced"
            }
        }

        var systemImage: String {
            switch self {
            case .reading:
                return "textformat.size"
            case .highlights:
                return "highlighter"
            case .navigation:
                return "point.topleft.down.curvedto.point.bottomright.up"
            case .advanced:
                return "slider.horizontal.3"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.height < 720
            NavigationSplitView {
                settingsSidebar
                    .frame(minWidth: 180, idealWidth: 200, maxWidth: 220)
            } detail: {
                ScrollView {
                    settingsContent(compact: compact)
                        .controlSize(compact ? .small : .regular)
                        .padding(compact ? 16 : 20)
                        .frame(maxWidth: 720, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: proxy.size.height)
            }
            .navigationSplitViewStyle(.balanced)
        }
        .frame(minWidth: 720, idealWidth: 860, maxWidth: 980, minHeight: 720, idealHeight: 780)
        .task {
            await refreshCacheMetrics()
        }
        .alert(
            pendingCacheAction?.confirmationTitle ?? "",
            isPresented: Binding(
                get: { pendingCacheAction != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingCacheAction = nil
                    }
                }
            ),
            presenting: pendingCacheAction
        ) { action in
            Button("Cancel", role: .cancel) {
                pendingCacheAction = nil
            }
            Button(action.confirmationButtonLabel, role: .destructive) {
                performCacheAction(action)
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    @ViewBuilder
    private func settingsContent(compact: Bool) -> some View {
        switch selectedSettingsSection ?? .reading {
        case .reading:
            readingExperienceSection(compact: compact)
        case .highlights:
            highlightsAndLabelsSection(compact: compact)
        case .navigation:
            navigationAndDiscoverSection(compact: compact)
        case .advanced:
            advancedControlsSection(compact: compact)
        }
    }

    private var settingsSidebar: some View {
        List(SettingsSection.allCases, selection: $selectedSettingsSection) { section in
            SwiftUI.Label(section.title, systemImage: section.systemImage)
                .tag(Optional(section))
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func readingExperienceSection(compact: Bool) -> some View {
        settingsSection(
            title: "Reading Experience",
            systemImage: "textformat.size",
            footer: "Reader changes apply immediately across article tabs.",
            compact: compact
        ) {
            Menu {
                ForEach(ReaderAppearancePreset.allCases) { preset in
                    Button {
                        applyPreset(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preset.rawValue)
                            Text(preset.summary)
                                .font(.caption)
                        }
                    }
                }
            } label: {
                LabeledContent("Preset") {
                    HStack(spacing: 6) {
                        Image(systemName: "slider.horizontal.3")
                        Text("Apply")
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary)
                }
            }

            settingDescription("Presets apply a balanced set of typography values for quick tuning.")

            Picker("Font", selection: $readerFontPreset) {
                ForEach(ReaderFontPreset.allCases, id: \.self) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .pickerStyle(.menu)

            settingDescription("Changes the article text and heading family used in the reader.")

            sliderRow(
                title: "Font Size",
                value: $readerFontSize,
                range: ReaderAppearance.fontSizeRange,
                step: 1,
                valueText: "\(Int(readerFontSize)) pt"
            )

            sliderRow(
                title: "Line Height",
                value: $readerLineHeight,
                range: ReaderAppearance.lineHeightRange,
                step: 0.05,
                valueText: readerLineHeight.formatted(.number.precision(.fractionLength(2)))
            )

            sliderRow(
                title: "Paragraph Spacing",
                value: $readerParagraphSpacing,
                range: ReaderAppearance.paragraphSpacingRange,
                step: 1,
                valueText: "\(Int(readerParagraphSpacing)) px"
            )

            DisclosureGroup(isExpanded: $showReaderFineTuning) {
                VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                    sliderRow(
                        title: "Content Width",
                        value: $readerContentWidth,
                        range: ReaderAppearance.contentWidthRange,
                        step: 10,
                        valueText: "\(Int(readerContentWidth)) px"
                    )

                    sliderRow(
                        title: "Side Margin",
                        value: $readerHorizontalPadding,
                        range: ReaderAppearance.horizontalPaddingRange,
                        step: 2,
                        valueText: "\(Int(readerHorizontalPadding)) px"
                    )

                    sliderRow(
                        title: "Heading Scale",
                        value: $readerHeadingScale,
                        range: ReaderAppearance.headingScaleRange,
                        step: 0.01,
                        valueText: "\(readerHeadingScale.formatted(.number.precision(.fractionLength(2))))x"
                    )

                    GroupBox("Preview") {
                        readerTypographyPreview(compact: compact)
                    }

                    Button("Reset Reader Defaults") {
                        resetReaderAppearance()
                    }
                }
                .padding(.top, compact ? 6 : 8)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fine-Tune Typography")
                    Text("Content width, margins, and heading scale with thin-window safety.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func highlightsAndLabelsSection(compact: Bool) -> some View {
        settingsSection(
            title: "Highlights & Labels",
            systemImage: "highlighter",
            footer: "These options control how label and highlight metadata appears in list and footer surfaces.",
            compact: compact
        ) {
            if compact {
                Picker("Label Display", selection: $labelDisplayMode) {
                    ForEach(LabelDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Label Display", selection: $labelDisplayMode) {
                    ForEach(LabelDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            settingDescription(labelStyleDescription(for: labelDisplayMode))

            if compact {
                Picker("Highlight Marker", selection: $highlightMarkerStyle) {
                    ForEach(HighlightMarkerStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Picker("Highlight Marker", selection: $highlightMarkerStyle) {
                    ForEach(HighlightMarkerStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.inline)
            }

            settingDescription(highlightMarkerDescription(for: highlightMarkerStyle))
        }
    }

    @ViewBuilder
    private func advancedControlsSection(compact: Bool) -> some View {
        settingsSection(
            title: "Advanced",
            systemImage: "slider.horizontal.3",
            footer: "Chrome, experiments, and storage controls live here.",
            compact: compact
        ) {
            VStack(alignment: .leading, spacing: compact ? 10 : 12) {
                if compact {
                    Picker("Advanced Area", selection: $selectedAdvancedPanel) {
                        ForEach(AdvancedPanel.allCases) { panel in
                            Text(panel.title).tag(panel)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    Picker("Advanced Area", selection: $selectedAdvancedPanel) {
                        ForEach(AdvancedPanel.allCases) { panel in
                            Text(panel.title).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                settingDescription(selectedAdvancedPanel.subtitle)

                GroupBox {
                    advancedPanelContent(compact: compact)
                }
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.18),
                    value: selectedAdvancedPanel
                )
            }
        }
    }

    @ViewBuilder
    private func navigationAndDiscoverSection(compact: Bool) -> some View {
        settingsSection(
            title: "Navigation & Discover",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            footer: "Navigation preferences control where discovery surfaces open and how the reader chrome behaves.",
            compact: compact
        ) {
            Picker("Discover Button Opens", selection: $discoverOpenMode) {
                ForEach(DiscoverOpenMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            settingDescription("Choose whether sidebar Discover opens directory sections or the full reader Discover page.")

            Picker("Search Presentation", selection: $searchPresentationMode) {
                ForEach(SearchPresentationMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.menu)

            settingDescription("Choose whether Wikipedia search appears as a floating command palette near the top of the window or directly inside the List Contents sidebar.")

            settingDescription("Discover start surface and tab chrome details are grouped under Advanced > Chrome.")

            Picker("Recents Shows", selection: $recentsScope) {
                ForEach(RecentsScope.allCases, id: \.self) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.menu)
            settingDescription("Choose whether the Recents directory lists the active tab’s history or your most recently opened articles across all tabs.")
        }
    }

    @ViewBuilder
    private func advancedPanelContent(compact: Bool) -> some View {
        switch selectedAdvancedPanel {
        case .chrome:
            advancedChromePanel(compact: compact)
        case .experiments:
            advancedExperimentsPanel()
        case .storage:
            advancedStoragePanel()
        }
    }

    @ViewBuilder
    private func advancedChromePanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            if isWikiHopAvailable {
                Picker("Discover Start Surface", selection: discoverStartModeBinding) {
                    ForEach(DiscoverStartMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                settingDescription("Choose the default view when opening a new tab.")
            }

            Toggle("Liquid Glass Tab Bar", isOn: $tabBarLiquidGlass)
            settingDescription("Use translucent liquid-glass treatment for the reader tab bar and article toolbar controls. Disable for a more solid chrome look.")

            GroupBox("Tab Accompaniments (Pro)") {
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    Toggle("Saved Marker", isOn: $showSavedTabMarker)
                    Toggle("Highlight Marker", isOn: $showHighlightTabMarker)
                    Toggle("Read Marker", isOn: $showReadTabMarker)
                    Toggle("Reading Progress Rail", isOn: $showTabProgressTrack)
                    Toggle("Active Tab Depth", isOn: $showTabActiveDepth)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            settingDescription("Optional power-user markers and depth cues for people who want more state visible in the reader tab strip.")

            GroupBox("Highlight Behavior") {
                VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                    Toggle("Wrap Highlight Header", isOn: $highlightHeaderWrap)
                    Toggle("Native Highlighting Menu", isOn: $nativeHighlightingMenuEnabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            settingDescription("Wrap enables long highlight section titles to continue on multiple lines. Native menu uses macOS text-selection highlighting in the article view.")

            GroupBox("Toolbar") {
                Text("Open `View > Customize Toolbar…` from the menu bar to show, hide, and rearrange toolbar controls.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func advancedExperimentsPanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if wikiHopPostV1Enabled {
                Toggle("Enable Wiki-Hop (POC)", isOn: Binding(
                    get: { wikiHopPOCEnabled },
                    set: { newValue in
                        appState.setWikiHopExperimentEnabled(newValue)
                    }
                ))
                settingDescription("A game of Wikipedia navigation. Get from a start article to a target article using only links.")
            } else {
                Text("Wiki-Hop is deferred to the post-v1 roadmap and hidden in the current build.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func advancedStoragePanel() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cacheMetrics {
                cacheMetricsCard(cacheMetrics)
            } else {
                AppLoadingInlineLabel(
                    text: "Loading cache stats…",
                    tone: .accent,
                    font: .footnote.weight(.medium)
                )
            }

            if performanceMetrics.hasSamples {
                performanceMetricsCard(performanceMetrics.summaries)
            } else {
                settingDescription("Performance samples appear here after session restore, search, sidebar hydration, and reader opens run at least once.")
            }

            HStack(spacing: 8) {
                Button("Refresh Stats") {
                    Task {
                        await refreshCacheMetrics()
                    }
                }
                .disabled(isCacheActionRunning)

                if isCacheActionRunning {
                    AppLoadingActivityMark(tone: .accent)
                }

                Spacer()
            }

            Button("Clear Performance Samples") {
                performanceMetrics.clear()
            }
            .disabled(!performanceMetrics.hasSamples)

            if let cacheStatusMessage {
                settingDescription(cacheStatusMessage)
            }

            Button("Clear Memory Cache") {
                queueCacheAction(.clearMemory)
            }
            .disabled(isCacheActionRunning)

            Button("Clear Temporary Disk Cache") {
                queueCacheAction(.clearTemporaryDisk)
            }
            .disabled(isCacheActionRunning)

            Button("Clear All Article Cache", role: .destructive) {
                queueCacheAction(.clearAllArticleCache)
            }
            .disabled(isCacheActionRunning)

            Divider()

            Button("Reset All App Data", role: .destructive) {
                queueCacheAction(.resetAllAppData)
            }
            .disabled(isCacheActionRunning)

            settingDescription("Use temporary clear for routine cleanup. Use full clear to reset article cache only. Use app reset only when you want a full local factory reset.")
            settingDescription("Saved, highlighted, and tagged articles are pinned in disk cache until you run a full article cache clear.")
            settingDescription("Performance samples are rolling summaries over the last 30 runs per path and persist across launches.")
        }
    }

    private var discoverStartModeBinding: Binding<DiscoverStartMode> {
        Binding(
            get: {
                let rawValue = UserDefaults.standard.string(forKey: DiscoverStartMode.storageKey) ?? DiscoverStartMode.discoverFeed.rawValue
                return DiscoverStartMode(rawValue: rawValue) ?? .discoverFeed
            },
            set: {
                UserDefaults.standard.set($0.rawValue, forKey: DiscoverStartMode.storageKey)
            }
        )
    }

    private func labelStyleDescription(for mode: LabelDisplayMode) -> String {
        switch mode {
        case .coloredDot:
            return "Changes the color of the unread indicator to match the assigned label."
        case .rowHighlight:
            return "Adds a subtle background color to the entire article row matching the label."
        }
    }

    private func highlightMarkerDescription(for style: HighlightMarkerStyle) -> String {
        switch style {
        case .dot:
            return "Use a circular color marker for highlights."
        case .bar:
            return "Use a slim color bar for highlights."
        case .background:
            return "Tint the entire highlight row using the highlight color."
        }
    }

    private var configuredReaderAppearance: ReaderAppearance {
        ReaderAppearance(
            fontPreset: readerFontPreset,
            fontSize: readerFontSize,
            lineHeight: readerLineHeight,
            paragraphSpacing: readerParagraphSpacing,
            contentWidth: readerContentWidth,
            horizontalPadding: readerHorizontalPadding,
            headingScale: readerHeadingScale
        )
    }

    private func previewFont(for preset: ReaderFontPreset, size: Double) -> Font {
        switch preset {
        case .system:
            return .system(size: size)
        case .newYork:
            return .custom("New York", size: size)
        case .charter:
            return .custom("Charter", size: size)
        case .iowan:
            return .custom("Iowan Old Style", size: size)
        case .palatino:
            return .custom("Palatino", size: size)
        }
    }

    private func previewBodyFont(for appearance: ReaderAppearance) -> Font {
        previewFont(for: appearance.fontPreset, size: appearance.fontSize)
    }

    private func previewHeadingFont(for appearance: ReaderAppearance) -> Font {
        let headingSize = appearance.fontSize * 1.7 * appearance.headingScale
        return previewFont(for: appearance.fontPreset, size: headingSize).weight(.semibold)
    }

    private func previewBodyLineSpacing(for appearance: ReaderAppearance) -> CGFloat {
        max(0, (appearance.lineHeight - 1.0) * appearance.fontSize)
    }

    @ViewBuilder
    private func readerTypographyPreview(compact: Bool) -> some View {
        GeometryReader { proxy in
            let viewportWidth = max(Double(proxy.size.width), 1)
            let resolved = configuredReaderAppearance.resolvedForViewportWidth(viewportWidth)
            let scaledPadding = resolved.horizontalPadding * (compact ? 0.35 : 0.45)
            let previewInlinePadding = max(8, min(40, scaledPadding))
            let availableTextWidth = max(
                proxy.size.width - (previewInlinePadding * 2),
                0
            )
            let previewColumnWidth = min(
                CGFloat(max(resolved.contentWidth, 0)),
                availableTextWidth
            )

            VStack(alignment: .leading, spacing: max(8, resolved.paragraphSpacing * 0.35)) {
                Text("Article Heading")
                    .font(previewHeadingFont(for: resolved))
                Text("This is a live preview of your reading typography settings for the article renderer.")
                    .font(previewBodyFont(for: resolved))
                    .lineSpacing(previewBodyLineSpacing(for: resolved))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: previewColumnWidth, alignment: .leading)
            .padding(.horizontal, previewInlinePadding)
            .padding(.vertical, compact ? 8 : 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: compact ? 138 : 156)
    }

    @ViewBuilder
    private func cacheMetricsCard(_ metrics: WikipediaService.CacheMetrics) -> some View {
        let inMemoryEntries = metrics.fullArticleEntries + metrics.fastArticleEntries
        let inMemoryBytes = metrics.fullArticleBytes + metrics.fastArticleBytes

        GroupBox("Article Cache Usage") {
            VStack(alignment: .leading, spacing: 8) {
                cacheMetricRow(
                    title: "In-Memory (Session)",
                    value: "\(formatByteCount(inMemoryBytes)) • \(entryCountLabel(inMemoryEntries))"
                )
                cacheMetricRow(
                    title: "Disk (Across Sessions)",
                    value: "\(formatByteCount(metrics.diskArticleBytes)) • \(entryCountLabel(metrics.diskArticleEntries))"
                )
                cacheMetricRow(
                    title: "Pinned on Disk",
                    value: articleCountLabel(metrics.pinnedArticleEntries)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func performanceMetricsCard(_ summaries: [PerformanceMetricsStore.Summary]) -> some View {
        GroupBox("Performance Samples") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                    performanceMetricSummaryRow(summary)
                    if index < summaries.count - 1 {
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func performanceMetricSummaryRow(_ summary: PerformanceMetricsStore.Summary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SwiftUI.Label(summary.kind.title, systemImage: summary.kind.symbolName)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(PerformanceMetricsStore.formatDuration(summary.lastDurationMs)) last")
                    .font(.caption.monospacedDigit())
            }

            Text(
                "avg \(PerformanceMetricsStore.formatDuration(summary.averageDurationMs)) • best \(PerformanceMetricsStore.formatDuration(summary.bestDurationMs)) • worst \(PerformanceMetricsStore.formatDuration(summary.worstDurationMs)) • \(entryCountLabel(summary.sampleCount))"
            )
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            Text(summary.lastDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func cacheMetricRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Slider(value: value, in: range, step: step)
        }
    }

    @ViewBuilder
    private func settingDescription(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        systemImage: String,
        footer: String,
        compact: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                content()
            }
            .padding(compact ? 12 : 14)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }
            Text(footer)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func queueCacheAction(_ action: CacheAction) {
        if action.requiresConfirmation {
            pendingCacheAction = action
        } else {
            performCacheAction(action)
        }
    }

    private func performCacheAction(_ action: CacheAction) {
        pendingCacheAction = nil
        guard !isCacheActionRunning else { return }

        isCacheActionRunning = true
        cacheStatusMessage = nil

        Task {
            let service = WikipediaService.shared
            var statusMessage = action.successMessage
            switch action {
            case .clearMemory:
                await service.clearInMemoryArticleCache()
            case .clearTemporaryDisk:
                await service.clearDiskArticleCache(includePinned: false)
            case .clearAllArticleCache:
                await service.clearInMemoryArticleCache()
                await service.clearDiskArticleCache(includePinned: true)
            case .resetAllAppData:
                do {
                    try await resetAllAppData(using: service)
                } catch {
                    statusMessage = "Reset failed. Please try again."
                }
            }

            let updatedMetrics = await service.cacheMetrics()
            await MainActor.run {
                cacheMetrics = updatedMetrics
                isCacheActionRunning = false
                cacheStatusMessage = statusMessage
            }
        }
    }

    private func resetAllAppData(using service: WikipediaService) async throws {
        await service.clearCache()
        try await MainActor.run {
            try deleteAllPersistedModels()
            resetUserDefaultsDomain()
            appState.resetForFactoryDefaults()
        }
    }

    private func deleteAllPersistedModels() throws {
        try deleteAllModels(of: ArticleNote.self)
        try deleteAllModels(of: Highlight.self)
        try deleteAllModels(of: ArticleState.self)
        try deleteAllModels(of: SavedArticle.self)
        try deleteAllModels(of: ReadingList.self)
        try deleteAllModels(of: Area.self)
        try deleteAllModels(of: Label.self)
        try deleteAllModels(of: Tag.self)
        try modelContext.save()
    }

    private func deleteAllModels<ModelType: PersistentModel>(of type: ModelType.Type) throws {
        let descriptor = FetchDescriptor<ModelType>()
        let models = try modelContext.fetch(descriptor)
        for model in models {
            modelContext.delete(model)
        }
    }

    private func resetUserDefaultsDomain() {
        _ = AppDefaultsReset.clearCandidateDomains()
    }

    private func refreshCacheMetrics() async {
        let metrics = await WikipediaService.shared.cacheMetrics()
        await MainActor.run {
            cacheMetrics = metrics
        }
    }

    private func formatByteCount(_ bytes: Int) -> String {
        Self.cacheByteFormatter.string(fromByteCount: Int64(max(bytes, 0)))
    }

    private func entryCountLabel(_ count: Int) -> String {
        count == 1 ? "1 entry" : "\(count) entries"
    }

    private func articleCountLabel(_ count: Int) -> String {
        count == 1 ? "1 article" : "\(count) articles"
    }

    private func resetReaderAppearance() {
        let defaults = ReaderAppearance.default
        readerFontPreset = defaults.fontPreset
        readerFontSize = defaults.fontSize
        readerLineHeight = defaults.lineHeight
        readerParagraphSpacing = defaults.paragraphSpacing
        readerContentWidth = defaults.contentWidth
        readerHorizontalPadding = defaults.horizontalPadding
        readerHeadingScale = defaults.headingScale
    }

    private func applyPreset(_ preset: ReaderAppearancePreset) {
        let appearance = preset.appearance
        readerFontPreset = appearance.fontPreset
        readerFontSize = appearance.fontSize
        readerLineHeight = appearance.lineHeight
        readerParagraphSpacing = appearance.paragraphSpacing
        readerContentWidth = appearance.contentWidth
        readerHorizontalPadding = appearance.horizontalPadding
        readerHeadingScale = appearance.headingScale
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .modelContainer(for: [ReadingList.self, SavedArticle.self, Area.self, Label.self, Tag.self, Highlight.self, ArticleNote.self, ArticleState.self], inMemory: true)
}
