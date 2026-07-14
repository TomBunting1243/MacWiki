import SwiftUI
import SwiftData
import MacWikiSettingsCatalog

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .reading

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab(
                SettingsTab.reading.title,
                systemImage: SettingsTab.reading.systemImage,
                value: SettingsTab.reading
            ) {
                SettingsReadingPane()
            }

            Tab(
                SettingsTab.library.title,
                systemImage: SettingsTab.library.systemImage,
                value: SettingsTab.library
            ) {
                SettingsLibraryPane()
            }

            Tab(
                SettingsTab.navigation.title,
                systemImage: SettingsTab.navigation.systemImage,
                value: SettingsTab.navigation
            ) {
                SettingsNavigationPane()
            }

            Tab(
                SettingsTab.chrome.title,
                systemImage: SettingsTab.chrome.systemImage,
                value: SettingsTab.chrome
            ) {
                SettingsChromePane()
            }

            Tab(
                SettingsTab.advanced.title,
                systemImage: SettingsTab.advanced.systemImage,
                value: SettingsTab.advanced
            ) {
                SettingsAdvancedPane()
            }
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
