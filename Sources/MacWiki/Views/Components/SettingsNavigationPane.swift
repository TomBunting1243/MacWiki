import SwiftUI
import MacWikiSettingsCatalog

struct SettingsNavigationPane: View {
    @AppStorage(AppStorageKey.Discover.openMode) private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage(AppStorageKey.Discover.sidebarTimeMachineHidden) private var discoverSidebarTimeMachineHidden = false
    @AppStorage(AppStorageKey.Recents.scope) private var recentsScope: RecentsScope = .currentTab

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

                Toggle("Hide Sidebar Time Machine", isOn: $discoverSidebarTimeMachineHidden)
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
    }
}
