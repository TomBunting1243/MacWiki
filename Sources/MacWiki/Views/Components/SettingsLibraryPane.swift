import SwiftUI
import SwiftData
import MacWikiSettingsCatalog

struct SettingsLibraryPane: View {
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]

    @AppStorage(AppStorageKey.Labels.displayMode) private var labelDisplayMode: LabelDisplayMode = .rowHighlight
    @AppStorage(AppStorageKey.Highlights.markerStyle) private var highlightMarkerStyle: HighlightMarkerStyle = .dot
    @AppStorage(AppStorageKey.Highlights.headerWrap) private var highlightHeaderWrap = false
    @AppStorage(AppStorageKey.Chrome.nativeHighlightingMenuEnabled) private var nativeHighlightingMenuEnabled = AppStorageKey.Chrome.nativeHighlightingMenuEnabledDefault
    @AppStorage(AppStorageKey.ListsSidebar.sortOrder) private var listSortOrder: ListSortOrder = .updatedDate
    @AppStorage(AppStorageKey.OptionClickSave.defaultListID) private var defaultListID: String = ""

    var body: some View {
        let section = SettingsCatalog.section(.library)

        SettingsPaneContainer(
            title: section.title,
            summary: section.summary,
            systemImage: section.systemImage
        ) {
            SettingsGroup("Lists", systemImage: "list.bullet.rectangle") {
                Picker("Sidebar Sort", selection: $listSortOrder) {
                    ForEach(ListSortOrder.allCases, id: \.self) { sortOrder in
                        Text(sortOrder.rawValue).tag(sortOrder)
                    }
                }
                .pickerStyle(.menu)

                Picker("Default Save List", selection: $defaultListID) {
                    Text("Most Recent List").tag("")

                    if !defaultListID.isEmpty && rememberedDefaultList == nil {
                        Text("Missing List").tag(defaultListID)
                    }

                    ForEach(allLists) { list in
                        Text(list.name).tag(list.id.uuidString)
                    }
                }
                .pickerStyle(.menu)
                .disabled(allLists.isEmpty && defaultListID.isEmpty)

                if allLists.isEmpty {
                    SettingsHelpText("Create a reading list before choosing a fixed default save target.")
                } else {
                    SettingsHelpText("Most Recent List follows the newest list in the library. Choose a named list to keep option-click saves anchored to one destination.")
                }
            }

            SettingsGroup("Labels", systemImage: "tag") {
                Picker("Label Display", selection: $labelDisplayMode) {
                    ForEach(LabelDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.inline)

                SettingsHelpText(labelStyleDescription(for: labelDisplayMode))
            }

            SettingsGroup("Highlights", systemImage: "highlighter") {
                Picker("Highlight Marker", selection: $highlightMarkerStyle) {
                    ForEach(HighlightMarkerStyle.allCases, id: \.self) { style in
                        Text(style.rawValue).tag(style)
                    }
                }
                .pickerStyle(.inline)

                SettingsHelpText(highlightMarkerDescription(for: highlightMarkerStyle))

                Toggle("Wrap Highlight Header", isOn: $highlightHeaderWrap)
                SettingsHelpText("Long highlight section titles can wrap instead of being clipped.")

                Toggle("Native Highlighting Menu", isOn: $nativeHighlightingMenuEnabled)
                SettingsHelpText("Use the macOS text-selection menu for creating highlights inside article pages.")
            }
        }
    }

    private var rememberedDefaultList: ReadingList? {
        guard let rememberedID = UUID(uuidString: defaultListID) else { return nil }
        return allLists.first(where: { $0.id == rememberedID })
    }

    private func labelStyleDescription(for mode: LabelDisplayMode) -> String {
        switch mode {
        case .coloredDot:
            "Changes the color of the unread indicator to match the assigned label."
        case .rowHighlight:
            "Adds a subtle background color to the whole article row using the assigned label color."
        }
    }

    private func highlightMarkerDescription(for style: HighlightMarkerStyle) -> String {
        switch style {
        case .dot:
            "Use a circular color marker for highlights."
        case .bar:
            "Use a slim color bar for highlights."
        case .background:
            "Tint the entire highlight row using the highlight color."
        }
    }
}
