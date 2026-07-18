import Foundation

public enum SettingsCatalogSectionID: String, CaseIterable, Sendable {
    case reading
    case library
    case navigation
    case chrome
    case advanced
    case internalMemory
}

public struct SettingsCatalogSection: Identifiable, Sendable {
    public let id: SettingsCatalogSectionID
    public let title: String
    public let summary: String
    public let systemImage: String
    public let options: [SettingsCatalogOption]
}

public struct SettingsCatalogOption: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let storageKey: String?
    public let defaultValue: String?
    public let control: String
    public let values: [String]
    public let codeReference: String?
    public let appearsInSettings: Bool

    public init(
        id: String,
        title: String,
        summary: String,
        storageKey: String?,
        defaultValue: String?,
        control: String,
        values: [String] = [],
        codeReference: String?,
        appearsInSettings: Bool = true
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.storageKey = storageKey
        self.defaultValue = defaultValue
        self.control = control
        self.values = values
        self.codeReference = codeReference
        self.appearsInSettings = appearsInSettings
    }
}

public enum SettingsCatalog {
    public static let sections: [SettingsCatalogSection] = [
        SettingsCatalogSection(
            id: .reading,
            title: "Reading",
            summary: "Reader typography, page width, spacing, Contents placement, and link preview behavior.",
            systemImage: "textformat.size",
            options: [
                option(
                    id: "reading.fontPreset",
                    title: "Reader Font",
                    summary: "Text and heading family used in the article renderer.",
                    storageKey: "reader.fontPreset",
                    defaultValue: "New York",
                    control: "Picker",
                    values: ["System", "New York", "Charter", "Iowan Old Style", "Palatino"],
                    codeReference: "ReaderAppearanceStorageKey.fontPreset"
                ),
                option(
                    id: "reading.fontSize",
                    title: "Reader Font Size",
                    summary: "Base article body text size.",
                    storageKey: "reader.fontSize",
                    defaultValue: "17",
                    control: "Slider",
                    values: ["13...30 pt"],
                    codeReference: "ReaderAppearanceStorageKey.fontSize"
                ),
                option(
                    id: "reading.lineHeight",
                    title: "Reader Line Height",
                    summary: "Vertical rhythm for article body text.",
                    storageKey: "reader.lineHeight",
                    defaultValue: "1.65",
                    control: "Slider",
                    values: ["1.20...2.20"],
                    codeReference: "ReaderAppearanceStorageKey.lineHeight"
                ),
                option(
                    id: "reading.paragraphSpacing",
                    title: "Reader Paragraph Spacing",
                    summary: "Spacing after paragraphs in article text.",
                    storageKey: "reader.paragraphSpacing",
                    defaultValue: "16",
                    control: "Slider",
                    values: ["6...36 px"],
                    codeReference: "ReaderAppearanceStorageKey.paragraphSpacing"
                ),
                option(
                    id: "reading.contentWidth",
                    title: "Reader Content Width",
                    summary: "Maximum article text column width.",
                    storageKey: "reader.contentWidth",
                    defaultValue: "860",
                    control: "Slider",
                    values: ["420...1400 px"],
                    codeReference: "ReaderAppearanceStorageKey.contentWidth"
                ),
                option(
                    id: "reading.horizontalPadding",
                    title: "Reader Side Margin",
                    summary: "Horizontal padding around the article column.",
                    storageKey: "reader.horizontalPadding",
                    defaultValue: "40",
                    control: "Slider",
                    values: ["12...120 px"],
                    codeReference: "ReaderAppearanceStorageKey.horizontalPadding"
                ),
                option(
                    id: "reading.headingScale",
                    title: "Reader Heading Scale",
                    summary: "Scale factor applied to article heading sizes.",
                    storageKey: "reader.headingScale",
                    defaultValue: "1.0",
                    control: "Slider",
                    values: ["0.85...1.30"],
                    codeReference: "ReaderAppearanceStorageKey.headingScale"
                ),
                option(
                    id: "reading.linkPreviewImmediateModifier",
                    title: "Link Preview Immediate Reveal",
                    summary: "Modifier that reveals reader link previews without the normal hover delay.",
                    storageKey: "reader.linkPreviewImmediateModifier",
                    defaultValue: "Command",
                    control: "Picker",
                    values: ["Off", "Command"],
                    codeReference: "AppStorageKey.Reader.linkPreviewImmediateModifier"
                ),
                option(
                    id: "reading.tableOfContentsPlacement",
                    title: "Contents Location",
                    summary: "Keeps article Contents in the Inspector or moves it to a temporary Reader-edge overlay.",
                    storageKey: "reader.tableOfContentsPlacement",
                    defaultValue: "Inspector",
                    control: "Picker",
                    values: ["Inspector", "Left Overlay", "Right Overlay"],
                    codeReference: "AppStorageKey.Reader.tableOfContentsPlacement"
                )
            ]
        ),
        SettingsCatalogSection(
            id: .library,
            title: "Library",
            summary: "Saved-article organization, labels, highlights, and the option-click save flow.",
            systemImage: "books.vertical",
            options: [
                option(
                    id: "library.sidebarSortOrder",
                    title: "Library Sidebar Sort",
                    summary: "Default ordering for lists, labels, tags, and areas in the library sidebar.",
                    storageKey: "sidebarSortOrder",
                    defaultValue: "Updated",
                    control: "Picker",
                    values: ["Manual", "Name", "Created", "Updated", "Articles"],
                    codeReference: "AppStorageKey.ListsSidebar.sortOrder"
                ),
                option(
                    id: "library.defaultSaveList",
                    title: "Default Save List",
                    summary: "Remembered destination for option-click link saves.",
                    storageKey: "optionClickSave.defaultListID",
                    defaultValue: "Most Recent List",
                    control: "Picker",
                    values: ["Blank means most recent list", "Reading list UUID"],
                    codeReference: "AppStorageKey.OptionClickSave.defaultListID"
                ),
                option(
                    id: "library.labelDisplayMode",
                    title: "Label Display",
                    summary: "How article labels are visualized in list rows.",
                    storageKey: "labelDisplayMode",
                    defaultValue: "Row Highlight",
                    control: "Picker",
                    values: ["Colored Dot", "Row Highlight"],
                    codeReference: "AppStorageKey.Labels.displayMode"
                ),
                option(
                    id: "library.highlightMarkerStyle",
                    title: "Highlight Marker",
                    summary: "How highlight colors appear in highlight list rows.",
                    storageKey: "highlightMarkerStyle",
                    defaultValue: "Dot",
                    control: "Picker",
                    values: ["Dot", "Bar", "Background"],
                    codeReference: "AppStorageKey.Highlights.markerStyle"
                ),
                option(
                    id: "library.highlightHeaderWrap",
                    title: "Wrap Highlight Header",
                    summary: "Allows long highlight section titles to wrap instead of clipping.",
                    storageKey: "highlightHeaderWrap",
                    defaultValue: "Off",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "AppStorageKey.Highlights.headerWrap"
                )
            ]
        ),
        SettingsCatalogSection(
            id: .navigation,
            title: "Navigation",
            summary: "Discover entry points, new-tab defaults, Recents scope, and sidebar discovery chrome.",
            systemImage: "point.topleft.down.curvedto.point.bottomright.up",
            options: [
                option(
                    id: "navigation.discoverOpenMode",
                    title: "Discover Button Opens",
                    summary: "Chooses whether Discover opens the sidebar view or full reader page.",
                    storageKey: "discoverOpenMode",
                    defaultValue: "Sidebar",
                    control: "Picker",
                    values: ["Sidebar", "Reader Page"],
                    codeReference: "AppStorageKey.Discover.openMode"
                ),
                option(
                    id: "navigation.discoverStartMode",
                    title: "New Tab Starts With",
                    summary: "Default surface for a new Discover tab.",
                    storageKey: "discoverStartMode",
                    defaultValue: "Discover Feed",
                    control: "Picker",
                    values: ["Discover Feed", "Wiki-Hop"],
                    codeReference: "DiscoverStartMode.storageKey",
                    appearsInSettings: false
                ),
                option(
                    id: "navigation.hideSidebarTimeMachine",
                    title: "Hide Sidebar Time Machine",
                    summary: "Hides the temporal Discover control in the sidebar.",
                    storageKey: "discover.sidebar.timeMachineHidden",
                    defaultValue: "Off",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "AppStorageKey.Discover.sidebarTimeMachineHidden"
                ),
                option(
                    id: "navigation.recentsScope",
                    title: "Recents Shows",
                    summary: "Chooses whether Recents follows the current tab or all opened articles.",
                    storageKey: "recentsScope",
                    defaultValue: "Current Tab",
                    control: "Picker",
                    values: ["Current Tab", "All Tabs"],
                    codeReference: "AppStorageKey.Recents.scope"
                )
            ]
        ),
        SettingsCatalogSection(
            id: .chrome,
            title: "Chrome",
            summary: "Window glass, tab-strip treatment, and reader tab state markers.",
            systemImage: "rectangle.topthird.inset.filled",
            options: [
                option(
                    id: "chrome.tabBarLiquidGlass",
                    title: "Liquid Glass Chrome",
                    summary: "Uses translucent Liquid Glass treatment for custom reader tabs, floating overlays, and top chrome.",
                    storageKey: "tabBarLiquidGlass",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "AppStorageKey.Chrome.liquidGlassChrome"
                ),
                option(
                    id: "chrome.forceLegacyGlassFallback",
                    title: "Use Legacy Glass Fallbacks",
                    summary: "Disables macOS 26 glass APIs and uses older material-based rendering.",
                    storageKey: "forceLegacyGlassFallback",
                    defaultValue: "Off",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "MacWikiGlassRuntime.forceLegacyFallbackKey"
                ),
                option(
                    id: "chrome.tabSavedMarker",
                    title: "Saved Tab Marker",
                    summary: "Shows saved state in reader tabs.",
                    storageKey: "tabs.accompaniment.savedMarker",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "TabAccompanimentStorageKey.showSavedMarker"
                ),
                option(
                    id: "chrome.tabHighlightMarker",
                    title: "Highlight Tab Marker",
                    summary: "Shows highlight state in reader tabs.",
                    storageKey: "tabs.accompaniment.highlightMarker",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "TabAccompanimentStorageKey.showHighlightMarker"
                ),
                option(
                    id: "chrome.tabReadMarker",
                    title: "Read Tab Marker",
                    summary: "Shows read state in reader tabs.",
                    storageKey: "tabs.accompaniment.readMarker",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "TabAccompanimentStorageKey.showReadMarker"
                ),
                option(
                    id: "chrome.tabProgressTrack",
                    title: "Reading Progress Rail",
                    summary: "Shows article reading progress in reader tabs.",
                    storageKey: "tabs.accompaniment.progressTrack",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "TabAccompanimentStorageKey.showProgressTrack"
                ),
                option(
                    id: "chrome.tabActiveDepth",
                    title: "Active Tab Depth",
                    summary: "Adds depth treatment to the active reader tab.",
                    storageKey: "tabs.accompaniment.activeDepth",
                    defaultValue: "On",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "TabAccompanimentStorageKey.showActiveDepth"
                )
            ]
        ),
        SettingsCatalogSection(
            id: .advanced,
            title: "Advanced",
            summary: "Experimental features, cache maintenance, local resets, and performance samples.",
            systemImage: "gearshape.2",
            options: [
                option(
                    id: "advanced.wikiHopExperiment",
                    title: "Enable Wiki-Hop",
                    summary: "Turns on the Wiki-Hop proof of concept when the broader feature gate is enabled.",
                    storageKey: "experiments.wikiHopPOCEnabled",
                    defaultValue: "Off",
                    control: "Toggle",
                    values: ["On", "Off"],
                    codeReference: "ExperimentFlag.wikiHopPOCEnabled.key",
                    appearsInSettings: false
                ),
                option(
                    id: "advanced.wikiHopPostV1Gate",
                    title: "Wiki-Hop Post-v1 Feature Gate",
                    summary: "Internal gate that keeps Wiki-Hop deferred until post-v1 work is enabled.",
                    storageKey: "features.wikiHopPostV1Enabled",
                    defaultValue: "Off",
                    control: "Internal toggle",
                    values: ["On", "Off"],
                    codeReference: "AppStorageKey.Features.wikiHopPostV1Enabled",
                    appearsInSettings: false
                ),
                action(
                    id: "advanced.refreshCacheStats",
                    title: "Refresh Cache Stats",
                    summary: "Reloads article cache usage metrics.",
                    control: "Button"
                ),
                action(
                    id: "advanced.clearMemoryCache",
                    title: "Clear Memory Cache",
                    summary: "Clears in-memory article cache for the current app session.",
                    control: "Button"
                ),
                action(
                    id: "advanced.clearTemporaryDiskCache",
                    title: "Clear Temporary Disk Cache",
                    summary: "Clears non-pinned disk-cached articles while preserving saved, highlighted, and tagged cache.",
                    control: "Destructive button"
                ),
                action(
                    id: "advanced.clearAllArticleCache",
                    title: "Clear All Article Cache",
                    summary: "Clears all article cache data, including pinned article cache.",
                    control: "Destructive button"
                ),
                action(
                    id: "advanced.resetAllAppData",
                    title: "Reset All App Data",
                    summary: "Removes local lists, saved articles, highlights, notes, labels, tags, reading state, tabs, cache, and preferences.",
                    control: "Destructive button"
                ),
                action(
                    id: "advanced.clearPerformanceSamples",
                    title: "Clear Performance Samples",
                    summary: "Clears rolling runtime performance summaries.",
                    control: "Button"
                )
            ]
        ),
        SettingsCatalogSection(
            id: .internalMemory,
            title: "Internal Layout Memory",
            summary: "Persisted layout state that is indexed for completeness but not exposed as a preference.",
            systemImage: "rectangle.split.3x1",
            options: [
                option(
                    id: "internal.mainWindowSidebarWidth",
                    title: "Main Window Sidebar Width",
                    summary: "Restores the left navigation sidebar width after relaunch.",
                    storageKey: "mainWindow.sidebarWidth",
                    defaultValue: "220",
                    control: "Layout memory",
                    values: ["176...260 pt"],
                    codeReference: "AppStorageKey.MainWindow.sidebarWidth",
                    appearsInSettings: false
                ),
                option(
                    id: "internal.mainWindowDirectoryWidth",
                    title: "Main Window Directory Width",
                    summary: "Restores the article directory column width after relaunch.",
                    storageKey: "mainWindow.directoryWidth",
                    defaultValue: "320",
                    control: "Layout memory",
                    values: ["260...420 pt"],
                    codeReference: "AppStorageKey.MainWindow.directoryWidth",
                    appearsInSettings: false
                ),
                option(
                    id: "internal.mainWindowInspectorWidth",
                    title: "Main Window Inspector Width",
                    summary: "Restores the inspector column width after relaunch.",
                    storageKey: "mainWindow.inspectorWidth",
                    defaultValue: "320",
                    control: "Layout memory",
                    values: ["320...460 pt"],
                    codeReference: "AppStorageKey.MainWindow.inspectorWidth",
                    appearsInSettings: false
                ),
                option(
                    id: "internal.articleWindowInspectorWidth",
                    title: "Article Window Inspector Width",
                    summary: "Restores dedicated article-window inspector width after relaunch without overwriting the main shell.",
                    storageKey: "articleWindow.inspectorWidth",
                    defaultValue: "320",
                    control: "Layout memory",
                    values: ["320...460 pt"],
                    codeReference: "AppStorageKey.ArticleWindow.inspectorWidth",
                    appearsInSettings: false
                )
            ]
        )
    ]

    public static var allOptions: [SettingsCatalogOption] {
        sections.flatMap(\.options)
    }

    public static var catalogedAppStorageReferences: Set<String> {
        Set(allOptions.compactMap(\.codeReference))
    }

    public static func section(_ id: SettingsCatalogSectionID) -> SettingsCatalogSection {
        guard let section = sections.first(where: { $0.id == id }) else {
            preconditionFailure("Missing settings catalog section: \(id.rawValue)")
        }
        return section
    }

    private static func option(
        id: String,
        title: String,
        summary: String,
        storageKey: String?,
        defaultValue: String?,
        control: String,
        values: [String] = [],
        codeReference: String?,
        appearsInSettings: Bool = true
    ) -> SettingsCatalogOption {
        SettingsCatalogOption(
            id: id,
            title: title,
            summary: summary,
            storageKey: storageKey,
            defaultValue: defaultValue,
            control: control,
            values: values,
            codeReference: codeReference,
            appearsInSettings: appearsInSettings
        )
    }

    private static func action(
        id: String,
        title: String,
        summary: String,
        control: String
    ) -> SettingsCatalogOption {
        SettingsCatalogOption(
            id: id,
            title: title,
            summary: summary,
            storageKey: nil,
            defaultValue: nil,
            control: control,
            codeReference: nil
        )
    }
}
