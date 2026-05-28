import Foundation
import Testing

import MacWikiSettingsCatalog
@testable import MacWiki

@MainActor
struct SettingsPreferencesPersistenceTests {
    @Test func everyVisiblePersistedPreferenceIsBoundInThePreferencesPanel() throws {
        let paneSources = try settingsPaneSources()
        let visiblePersistedOptions = SettingsCatalog.allOptions
            .filter(\.appearsInSettings)
            .filter { $0.storageKey != nil }

        let missingBindings = visiblePersistedOptions.compactMap { option -> String? in
            guard let codeReference = option.codeReference else { return option.id }
            return paneSources.contains("@AppStorage(\(codeReference))") ? nil : option.id
        }

        #expect(missingBindings.isEmpty, "Visible persisted settings without Preferences @AppStorage bindings: \(missingBindings)")
    }

    @Test func preferencesPanelExposesEachVisiblePersistedSettingControl() throws {
        let paneSources = try settingsPaneSources()
        let visiblePersistedOptions = SettingsCatalog.allOptions
            .filter(\.appearsInSettings)
            .filter { $0.storageKey != nil }

        for option in visiblePersistedOptions {
            #expect(
                paneSources.contains(option.control) || paneSources.contains(option.title) || paneSources.contains(preferencesLabel(for: option.id)),
                "Missing Preferences control surface for \(option.id)"
            )
        }
    }

    @Test func visiblePreferencesWriteValuesToTheirDocumentedStorageKeys() {
        let defaults = UserDefaults.standard
        let probes = visiblePreferenceProbes()
        let previousValues = probes.reduce(into: [String: Any]()) { result, probe in
            result[probe.storageKey] = defaults.object(forKey: probe.storageKey)
        }
        defer {
            for probe in probes {
                if let previousValue = previousValues[probe.storageKey] {
                    defaults.set(previousValue, forKey: probe.storageKey)
                } else {
                    defaults.removeObject(forKey: probe.storageKey)
                }
            }
        }

        for probe in probes {
            probe.write(defaults)
            #expect(
                probe.matches(defaults),
                "\(probe.id) did not persist expected value for key \(probe.storageKey)"
            )
        }
    }

    private func visiblePreferenceProbes() -> [PreferencePersistenceProbe] {
        [
            .string(id: "reading.fontPreset", storageKey: ReaderAppearanceStorageKey.fontPreset, value: ReaderFontPreset.charter.rawValue),
            .double(id: "reading.fontSize", storageKey: ReaderAppearanceStorageKey.fontSize, value: 21),
            .double(id: "reading.lineHeight", storageKey: ReaderAppearanceStorageKey.lineHeight, value: 1.9),
            .double(id: "reading.paragraphSpacing", storageKey: ReaderAppearanceStorageKey.paragraphSpacing, value: 22),
            .double(id: "reading.contentWidth", storageKey: ReaderAppearanceStorageKey.contentWidth, value: 980),
            .double(id: "reading.horizontalPadding", storageKey: ReaderAppearanceStorageKey.horizontalPadding, value: 56),
            .double(id: "reading.headingScale", storageKey: ReaderAppearanceStorageKey.headingScale, value: 1.08),
            .string(id: "reading.linkPreviewImmediateModifier", storageKey: AppStorageKey.Reader.linkPreviewImmediateModifier, value: ReaderLinkPreviewImmediateModifier.off.rawValue),
            .string(id: "library.sidebarSortOrder", storageKey: AppStorageKey.ListsSidebar.sortOrder, value: ListSortOrder.name.rawValue),
            .string(id: "library.defaultSaveList", storageKey: AppStorageKey.OptionClickSave.defaultListID, value: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!.uuidString),
            .string(id: "library.labelDisplayMode", storageKey: AppStorageKey.Labels.displayMode, value: LabelDisplayMode.coloredDot.rawValue),
            .string(id: "library.highlightMarkerStyle", storageKey: AppStorageKey.Highlights.markerStyle, value: HighlightMarkerStyle.background.rawValue),
            .bool(id: "library.highlightHeaderWrap", storageKey: AppStorageKey.Highlights.headerWrap, value: true),
            .string(id: "navigation.discoverOpenMode", storageKey: AppStorageKey.Discover.openMode, value: DiscoverOpenMode.readerPage.rawValue),
            .bool(id: "navigation.hideSidebarTimeMachine", storageKey: AppStorageKey.Discover.sidebarTimeMachineHidden, value: true),
            .string(id: "navigation.recentsScope", storageKey: AppStorageKey.Recents.scope, value: RecentsScope.allTabs.rawValue),
            .bool(id: "chrome.tabBarLiquidGlass", storageKey: AppStorageKey.Chrome.liquidGlassChrome, value: false),
            .bool(id: "chrome.forceLegacyGlassFallback", storageKey: MacWikiGlassRuntime.forceLegacyFallbackKey, value: true),
            .bool(id: "chrome.tabSavedMarker", storageKey: TabAccompanimentStorageKey.showSavedMarker, value: false),
            .bool(id: "chrome.tabHighlightMarker", storageKey: TabAccompanimentStorageKey.showHighlightMarker, value: false),
            .bool(id: "chrome.tabReadMarker", storageKey: TabAccompanimentStorageKey.showReadMarker, value: false),
            .bool(id: "chrome.tabProgressTrack", storageKey: TabAccompanimentStorageKey.showProgressTrack, value: false),
            .bool(id: "chrome.tabActiveDepth", storageKey: TabAccompanimentStorageKey.showActiveDepth, value: false)
        ]
    }

    private func settingsPaneSources() throws -> String {
        try [
            "Sources/MacWiki/Views/Components/SettingsReadingPane.swift",
            "Sources/MacWiki/Views/Components/SettingsLibraryPane.swift",
            "Sources/MacWiki/Views/Components/SettingsNavigationPane.swift",
            "Sources/MacWiki/Views/Components/SettingsChromePane.swift",
            "Sources/MacWiki/Views/Components/SettingsAdvancedPane.swift"
        ]
        .map { try source($0) }
        .joined(separator: "\n")
    }

    private func preferencesLabel(for optionID: String) -> String {
        switch optionID {
        case "reading.fontPreset":
            "Font"
        case "reading.fontSize":
            "Font Size"
        case "reading.lineHeight":
            "Line Height"
        case "reading.paragraphSpacing":
            "Paragraph Spacing"
        case "reading.contentWidth":
            "Content Width"
        case "reading.horizontalPadding":
            "Side Margin"
        case "reading.headingScale":
            "Heading Scale"
        case "reading.linkPreviewImmediateModifier":
            "Immediate Reveal"
        case "library.sidebarSortOrder":
            "Sidebar Sort"
        case "library.defaultSaveList":
            "Default Save List"
        case "library.labelDisplayMode":
            "Label Display"
        case "library.highlightMarkerStyle":
            "Highlight Marker"
        case "library.highlightHeaderWrap":
            "Wrap Highlight Header"
        case "navigation.discoverOpenMode":
            "Discover Button Opens"
        case "navigation.hideSidebarTimeMachine":
            "Hide Sidebar Time Machine"
        case "navigation.recentsScope":
            "Recents Shows"
        case "chrome.tabBarLiquidGlass":
            "Liquid Glass Chrome"
        case "chrome.forceLegacyGlassFallback":
            "Use Legacy Glass Fallbacks"
        case "chrome.tabSavedMarker":
            "Saved Marker"
        case "chrome.tabHighlightMarker":
            "Highlight Marker"
        case "chrome.tabReadMarker":
            "Read Marker"
        case "chrome.tabProgressTrack":
            "Reading Progress Rail"
        case "chrome.tabActiveDepth":
            "Active Tab Depth"
        default:
            optionID
        }
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

private struct PreferencePersistenceProbe {
    let id: String
    let storageKey: String
    let write: (UserDefaults) -> Void
    let matches: (UserDefaults) -> Bool

    static func bool(id: String, storageKey: String, value: Bool) -> Self {
        Self(
            id: id,
            storageKey: storageKey,
            write: { $0.set(value, forKey: storageKey) },
            matches: { $0.bool(forKey: storageKey) == value }
        )
    }

    static func double(id: String, storageKey: String, value: Double) -> Self {
        Self(
            id: id,
            storageKey: storageKey,
            write: { $0.set(value, forKey: storageKey) },
            matches: { $0.double(forKey: storageKey) == value }
        )
    }

    static func string(id: String, storageKey: String, value: String) -> Self {
        Self(
            id: id,
            storageKey: storageKey,
            write: { $0.set(value, forKey: storageKey) },
            matches: { $0.string(forKey: storageKey) == value }
        )
    }
}
