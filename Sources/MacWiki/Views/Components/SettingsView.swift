import SwiftUI
import SwiftData
import MacWikiSettingsCatalog

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .reading

    var body: some View {
        TabView(selection: $selectedTab) {
            SettingsReadingPane()
                .tabItem {
                    SwiftUI.Label(SettingsTab.reading.title, systemImage: SettingsTab.reading.systemImage)
                }
                .tag(SettingsTab.reading)

            SettingsLibraryPane()
                .tabItem {
                    SwiftUI.Label(SettingsTab.library.title, systemImage: SettingsTab.library.systemImage)
                }
                .tag(SettingsTab.library)

            SettingsNavigationPane()
                .tabItem {
                    SwiftUI.Label(SettingsTab.navigation.title, systemImage: SettingsTab.navigation.systemImage)
                }
                .tag(SettingsTab.navigation)

            SettingsChromePane()
                .tabItem {
                    SwiftUI.Label(SettingsTab.chrome.title, systemImage: SettingsTab.chrome.systemImage)
                }
                .tag(SettingsTab.chrome)

            SettingsAdvancedPane()
                .tabItem {
                    SwiftUI.Label(SettingsTab.advanced.title, systemImage: SettingsTab.advanced.systemImage)
                }
                .tag(SettingsTab.advanced)
        }
        .frame(minWidth: 620, idealWidth: 660, maxWidth: 760, minHeight: 600, idealHeight: 680)
    }
}

private enum SettingsTab: String, Hashable {
    case reading
    case library
    case navigation
    case chrome
    case advanced

    var title: String {
        SettingsCatalog.section(sectionID).title
    }

    var systemImage: String {
        SettingsCatalog.section(sectionID).systemImage
    }

    private var sectionID: SettingsCatalogSectionID {
        switch self {
        case .reading:
            .reading
        case .library:
            .library
        case .navigation:
            .navigation
        case .chrome:
            .chrome
        case .advanced:
            .advanced
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState(persistenceMode: .ephemeral))
        .modelContainer(
            for: [
                ReadingList.self,
                SavedArticle.self,
                Area.self,
                Label.self,
                Tag.self,
                Highlight.self,
                ArticleNote.self,
                ArticleState.self
            ],
            inMemory: true
        )
}
