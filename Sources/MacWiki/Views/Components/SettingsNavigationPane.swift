import SwiftUI
import MacWikiSettingsCatalog

struct SettingsNavigationPane: View {
    @AppStorage(AppStorageKey.Discover.openMode) private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage(DiscoverStartMode.storageKey) private var discoverStartMode: DiscoverStartMode = .discoverFeed
    @AppStorage(AppStorageKey.Discover.sidebarTimeMachineHidden) private var discoverSidebarTimeMachineHidden = false
    @AppStorage(AppStorageKey.Recents.scope) private var recentsScope: RecentsScope = .currentTab
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var wikiHopPOCEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var wikiHopPostV1Enabled = false

    var body: some View {
        let section = SettingsCatalog.section(.navigation)

        SettingsPaneContainer(
            title: section.title,
            summary: section.summary,
            systemImage: section.systemImage
        ) {
            SettingsGroup("Discover", systemImage: "safari") {
                Picker("Discover Button Opens", selection: $discoverOpenMode) {
                    ForEach(DiscoverOpenMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                if isWikiHopAvailable {
                    Picker("New Tab Starts With", selection: $discoverStartMode) {
                        ForEach(DiscoverStartMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                } else {
                    LabeledContent("New Tab Starts With") {
                        Text(DiscoverStartMode.discoverFeed.rawValue)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Hide Sidebar Time Machine", isOn: $discoverSidebarTimeMachineHidden)

                SettingsHelpText("Wiki-Hop only appears as a new-tab start option when both the post-v1 feature gate and the experiment are enabled.")
            }

            SettingsGroup("Recents", systemImage: "clock.arrow.circlepath") {
                Picker("Recents Shows", selection: $recentsScope) {
                    ForEach(RecentsScope.allCases, id: \.self) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.menu)

                SettingsHelpText("Current Tab follows the active reader tab. All Tabs shows the latest opened articles across the session.")
            }
        }
        .onChange(of: isWikiHopAvailable) { _, available in
            if !available && discoverStartMode == .wikiHop {
                discoverStartMode = .discoverFeed
            }
        }
    }

    private var isWikiHopAvailable: Bool {
        wikiHopPostV1Enabled && wikiHopPOCEnabled
    }
}
