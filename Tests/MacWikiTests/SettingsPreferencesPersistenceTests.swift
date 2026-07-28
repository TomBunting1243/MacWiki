import Testing

import MacWikiSettingsCatalog
@testable import MacWiki

@MainActor
struct SettingsPreferencesPersistenceTests {
    @Test func visiblePersistedPreferencesMatchRuntimeStorageKeysExactly() {
        let runtimeStorageKeysByOptionID: [String: String] = [
            "reading.fontPreset": ReaderAppearanceStorageKey.fontPreset,
            "reading.fontSize": ReaderAppearanceStorageKey.fontSize,
            "reading.lineHeight": ReaderAppearanceStorageKey.lineHeight,
            "reading.paragraphSpacing": ReaderAppearanceStorageKey.paragraphSpacing,
            "reading.contentWidth": ReaderAppearanceStorageKey.contentWidth,
            "reading.horizontalPadding": ReaderAppearanceStorageKey.horizontalPadding,
            "reading.headingScale": ReaderAppearanceStorageKey.headingScale,
            "reading.linkPreviewImmediateModifier": AppStorageKey.Reader.linkPreviewImmediateModifier,
            "reading.tableOfContentsPlacement": AppStorageKey.Reader.tableOfContentsPlacement,
            "library.sidebarSortOrder": AppStorageKey.ListsSidebar.sortOrder,
            "library.defaultSaveList": AppStorageKey.OptionClickSave.defaultListID,
            "library.labelDisplayMode": AppStorageKey.Labels.displayMode,
            "library.highlightMarkerStyle": AppStorageKey.Highlights.markerStyle,
            "library.highlightHeaderWrap": AppStorageKey.Highlights.headerWrap,
            "navigation.hideSidebarTimeMachine": AppStorageKey.Discover.sidebarTimeMachineHidden,
            "navigation.recentsScope": AppStorageKey.Recents.scope,
            "chrome.tabBarLiquidGlass": AppStorageKey.Chrome.liquidGlassChrome,
            "chrome.forceLegacyGlassFallback": MacWikiGlassRuntime.forceLegacyFallbackKey,
            "chrome.tabSavedMarker": TabAccompanimentStorageKey.showSavedMarker,
            "chrome.tabHighlightMarker": TabAccompanimentStorageKey.showHighlightMarker,
            "chrome.tabReadMarker": TabAccompanimentStorageKey.showReadMarker,
            "chrome.tabProgressTrack": TabAccompanimentStorageKey.showProgressTrack,
            "chrome.tabActiveDepth": TabAccompanimentStorageKey.showActiveDepth
        ]

        let catalogStorageKeysByOptionID = SettingsCatalog.allOptions.reduce(
            into: [String: String]()
        ) { result, option in
            guard option.appearsInSettings, let storageKey = option.storageKey else { return }
            result[option.id] = storageKey
        }

        #expect(runtimeStorageKeysByOptionID == catalogStorageKeysByOptionID)
    }
}
