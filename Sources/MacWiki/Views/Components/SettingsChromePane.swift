import SwiftUI
import MacWikiSettingsCatalog

struct SettingsChromePane: View {
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false
    @AppStorage(TabAccompanimentStorageKey.showSavedMarker) private var showSavedTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showHighlightMarker) private var showHighlightTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showReadMarker) private var showReadTabMarker = true
    @AppStorage(TabAccompanimentStorageKey.showProgressTrack) private var showTabProgressTrack = true
    @AppStorage(TabAccompanimentStorageKey.showActiveDepth) private var showTabActiveDepth = true

    var body: some View {
        let section = SettingsCatalog.section(.chrome)

        SettingsPaneContainer(
            title: section.title,
            summary: section.summary,
            systemImage: section.systemImage
        ) {
            SettingsGroup("Window Surfaces", systemImage: "sparkles.rectangle.stack") {
                AccessibleSettingsToggle("Liquid Glass Chrome", isOn: $liquidGlassChrome)
                SettingsHelpText("Use translucent Liquid Glass treatment for custom reader tabs, floating overlays, and top chrome.")

                AccessibleSettingsToggle("Use Legacy Glass Fallbacks", isOn: $forceLegacyGlassFallback)
                SettingsHelpText("Disable macOS 26 glass APIs and render the older material-based fallback path instead.")
            }

            SettingsGroup("Tab Accompaniments", systemImage: "rectangle.stack.badge.plus") {
                AccessibleSettingsToggle("Saved Marker", isOn: $showSavedTabMarker)
                AccessibleSettingsToggle("Highlight Marker", isOn: $showHighlightTabMarker)
                AccessibleSettingsToggle("Read Marker", isOn: $showReadTabMarker)
                AccessibleSettingsToggle("Reading Progress Rail", isOn: $showTabProgressTrack)
                AccessibleSettingsToggle("Active Tab Depth", isOn: $showTabActiveDepth)

                SettingsHelpText("These power-user cues keep saved, highlighted, read, and reading-position state visible across the reader tab strip, including inactive tabs.")
            }
        }
    }
}
