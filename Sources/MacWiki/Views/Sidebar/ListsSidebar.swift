import SwiftUI
import SwiftData

fileprivate enum SidebarDensityPreset: String, CaseIterable {
    case music = "music"
    case comfortable = "comfortable"

    var title: String {
        switch self {
        case .music:
            return "Music (Dense)"
        case .comfortable:
            return "Comfortable"
        }
    }
}

fileprivate enum SidebarMetrics {
    private static var densityPreset: SidebarDensityPreset {
        if let raw = UserDefaults.standard.string(forKey: "sidebarDensityPreset"),
           let preset = SidebarDensityPreset(rawValue: raw) {
            return preset
        }
        return .music
    }

    static var itemFontSize: CGFloat {
        densityPreset == .music ? 12.5 : 13
    }

    static var sectionHeaderFont: Font {
        densityPreset == .music
            ? Font.system(size: 10, weight: .semibold)
            : Font.system(size: 11, weight: .semibold)
    }

    static var itemFont: Font {
        Font.system(size: itemFontSize, weight: .regular)
    }

    static var itemIconFont: Font {
        Font.system(size: itemFontSize, weight: .regular)
    }

    static var sectionHeaderHeight: CGFloat {
        densityPreset == .music ? 24 : 28
    }

    static var itemIconWidth: CGFloat {
        16
    }

    static var trailingControlSize: CGFloat {
        densityPreset == .music ? 22 : 26
    }

    static var rowSpacing: CGFloat {
        densityPreset == .music ? 6 : 7
    }

    static var rowCornerRadius: CGFloat {
        11
    }

    static var rowMinimumHitHeight: CGFloat {
        densityPreset == .music ? 26 : 28
    }

    static var rowInsets: EdgeInsets {
        densityPreset == .music
            ? EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11)
            : EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12)
    }

    static var emptyStateVerticalPadding: CGFloat {
        densityPreset == .music ? 4 : 6
    }

    static func iconPrimaryOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.76 : 0.70
    }

    static func iconSelectedOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.94 : 0.88
    }

    static func iconHoverOpacity(darkMode: Bool) -> Double {
        darkMode ? 0.83 : 0.76
    }

    static func iconColor(
        for colorScheme: ColorScheme,
        isSelected: Bool,
        isHovered: Bool
    ) -> Color {
        let darkMode = colorScheme == .dark
        if isSelected {
            return Color.primary.opacity(iconSelectedOpacity(darkMode: darkMode))
        }
        if isHovered {
            return Color.primary.opacity(iconHoverOpacity(darkMode: darkMode))
        }
        return Color.primary.opacity(iconPrimaryOpacity(darkMode: darkMode))
    }

    static func titleColor(
        for colorScheme: ColorScheme,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.primary.opacity(iconSelectedOpacity(darkMode: colorScheme == .dark))
        }
        return Color.primary
    }

    static func countColor(
        for colorScheme: ColorScheme,
        isSelected: Bool
    ) -> Color {
        if isSelected {
            return Color.primary.opacity(colorScheme == .dark ? 0.84 : 0.76)
        }
        return Color(nsColor: .tertiaryLabelColor)
    }
}

private struct SidebarRowSurface: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    var isSelected: Bool = false
    var isHovered: Bool = false
    var isDropTarget: Bool = false

    private var dropTargetFill: Color {
        Color.accentColor.opacity(0.16)
    }

    private var selectedFill: Color {
        let isKeyWindow = controlActiveState == .key
        return Color.accentColor.opacity(
            colorScheme == .dark
                ? (isKeyWindow ? 0.24 : 0.18)
                : (isKeyWindow ? 0.18 : 0.14)
        )
    }

    private var hoverFill: Color {
        let isKeyWindow = controlActiveState == .key
        return colorScheme == .dark
            ? Color.white.opacity(isKeyWindow ? 0.070 : 0.050)
            : Color.black.opacity(isKeyWindow ? 0.038 : 0.024)
    }

    private var selectedStroke: Color {
        let isKeyWindow = controlActiveState == .key
        return Color.accentColor.opacity(
            colorScheme == .dark
                ? (isKeyWindow ? 0.42 : 0.30)
                : (isKeyWindow ? 0.30 : 0.22)
        )
    }

    private var hoverStroke: Color {
        let isKeyWindow = controlActiveState == .key
        return colorScheme == .dark
            ? Color.white.opacity(isKeyWindow ? 0.11 : 0.075)
            : Color.black.opacity(isKeyWindow ? 0.070 : 0.045)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
            .fill(
                isDropTarget
                    ? dropTargetFill
                    : (
                        isSelected
                            ? selectedFill
                            : ((isHovered && !isSelected) ? hoverFill : Color.clear)
                    )
            )
            .overlay {
                if isDropTarget || (isHovered && !isSelected) || isSelected {
                    RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous)
                        .strokeBorder(
                            isDropTarget
                                ? Color.accentColor.opacity(0.24)
                                : (isSelected ? selectedStroke : hoverStroke),
                            lineWidth: 0.75
                        )
                }
            }
    }
}

private enum SidebarSelectionID: Hashable {
    case search
    case root(SidebarRootSelection)
    case list(UUID)
    case label(UUID)
    case tag(UUID)
    case area(UUID)
}

private struct PendingAreaDeletion {
    let rootAreaIDs: [UUID]
    let folderCount: Int
    let listCount: Int
    let nestedFolderCount: Int

    var hasContents: Bool {
        listCount > 0 || nestedFolderCount > 0
    }
}

/// Lists sidebar with reading lists management
struct ListsSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var lists: [ReadingList]
    @Query private var areas: [Area]
    @Query private var savedArticles: [SavedArticle]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \ArticleState.updatedAt, order: .reverse) private var articleStates: [ArticleState]
    
    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    @State private var showNewListSheet = false
    @State private var showNewAreaSheet = false
    @State private var sidebarSelection: SidebarSelectionID?
    @State private var selectedAreaIDs: Set<UUID> = []
    @AppStorage("sidebarSortOrder") private var sortOrder: ListSortOrder = .updatedDate
    @AppStorage("sidebarDensityPreset") private var sidebarDensityPreset: SidebarDensityPreset = .music
    
    // Editing state for lists
    @State private var editingList: ReadingList?
    @State private var editingName: String = ""
    @State private var showRenameAlert = false
    @State private var iconPickerList: ReadingList?
    @State private var showIconPickerSheet = false
    @AppStorage("discoverOpenMode") private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var isWikiHopEnabled = false
    @AppStorage("features.wikiHopPostV1Enabled") private var isWikiHopPostV1Enabled = false

    // Editing state for areas
    @State private var editingArea: Area?
    @State private var editingAreaName: String = ""
    @State private var showAreaRenameAlert = false
    @State private var pendingAreaDeletion: PendingAreaDeletion?
    @State private var showAreaDeleteContentsPrompt = false

    // Tag management
    @State private var showNewTagSheet = false
    @State private var editingTag: Tag?

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]
    
    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    enum ListSortOrder: String, CaseIterable {
        case manual = "Manual"
        case name = "Name"
        case createdDate = "Created"
        case updatedDate = "Updated"
        case articleCount = "Articles"
    }

    private var trimmedEditingName: String {
        editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEditingAreaName: String {
        editingAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedSelection: SidebarSelectionID {
        if appState.showSearch {
            return .search
        }
        if let listId = selectedList?.id {
            return .list(listId)
        }
        if let labelId = selectedLabel?.id {
            return .label(labelId)
        }
        if let tagId = selectedTag?.id {
            return .tag(tagId)
        }
        if let areaId = selectedAreaIDs.sorted(by: { $0.uuidString < $1.uuidString }).first {
            return .area(areaId)
        }
        if rootSelection == .wikiHop && !isWikiHopAvailable {
            return .root(.recents)
        }
        return .root(rootSelection)
    }

    private var isWikiHopAvailable: Bool {
        isWikiHopPostV1Enabled && isWikiHopEnabled
    }

    private var sortedLists: [ReadingList] {
        switch sortOrder {
        case .manual:
            return lists.sorted(by: compareListsForManualSort)
        case .name:
            return lists.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .createdDate:
            return lists.sorted { $0.createdAt > $1.createdAt }
        case .updatedDate:
            return lists.sorted { $0.updatedAt > $1.updatedAt }
        case .articleCount:
            return lists.sorted { $0.articles.count > $1.articles.count }
        }
    }
    
    /// Lists not in any area
    private var rootLevelLists: [ReadingList] {
        sortedLists.filter { $0.areaId == nil }
    }
    
    /// Lists within a specific area
    private func listsInArea(_ area: Area) -> [ReadingList] {
        sortedLists.filter { $0.areaId == area.id }
    }

    /// Root-level areas (not nested under another area)
    private var rootAreas: [Area] {
        areas.filter { $0.parentId == nil }.sorted(by: compareAreasForSortOrder)
    }

    /// Child areas within a specific parent area
    private func childAreas(of parent: Area) -> [Area] {
        areas.filter { $0.parentId == parent.id }.sorted(by: compareAreasForSortOrder)
    }

    private var sortedLabels: [Label] {
        labels.sorted(by: compareLabelsForSortOrder)
    }

    private var sortedTags: [Tag] {
        tags.sorted(by: compareTagsForSortOrder)
    }

    private var labelArticleCounts: [UUID: Int] {
        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(sortedLabels.count)
        for article in savedArticles {
            guard let labelId = article.labelId else { continue }
            counts[labelId, default: 0] += 1
        }
        return counts
    }

    private var tagArticleCounts: [UUID: Int] {
        var titlesByTag: [UUID: Set<String>] = [:]
        titlesByTag.reserveCapacity(sortedTags.count)

        for highlight in highlights {
            for tag in highlight.tags {
                titlesByTag[tag.id, default: []].insert(highlight.articleTitle)
            }
        }

        for state in articleStates {
            for tag in state.tags {
                titlesByTag[tag.id, default: []].insert(state.articleTitle)
            }
        }

        var counts: [UUID: Int] = [:]
        counts.reserveCapacity(titlesByTag.count)
        for (tagId, titles) in titlesByTag {
            counts[tagId] = titles.count
        }
        return counts
    }

    private func compareListsForManualSort(_ lhs: ReadingList, _ rhs: ReadingList) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compareAreasForSortOrder(_ lhs: Area, _ rhs: Area) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compareLabelsForSortOrder(_ lhs: Label, _ rhs: Label) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private func compareTagsForSortOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
        if lhs.sortOrder != rhs.sortOrder {
            return lhs.sortOrder < rhs.sortOrder
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private var areaIndexByID: [UUID: Area] {
        Dictionary(uniqueKeysWithValues: areas.map { ($0.id, $0) })
    }

    private var areaDeleteDialogTitle: String {
        guard let pendingAreaDeletion else { return "Delete folder contents?" }
        return pendingAreaDeletion.folderCount == 1
            ? "Delete folder contents?"
            : "Delete selected folder contents?"
    }

    private var areaDeleteDialogMessage: String {
        guard let pendingAreaDeletion else { return "" }
        let listDescription = "\(pendingAreaDeletion.listCount) list\(pendingAreaDeletion.listCount == 1 ? "" : "s")"
        let nestedDescription = "\(pendingAreaDeletion.nestedFolderCount) nested folder\(pendingAreaDeletion.nestedFolderCount == 1 ? "" : "s")"

        if pendingAreaDeletion.listCount > 0 && pendingAreaDeletion.nestedFolderCount > 0 {
            return "The selected folder\(pendingAreaDeletion.folderCount == 1 ? "" : "s") contain \(listDescription) and \(nestedDescription). Choose whether to move contents to root or delete them."
        }

        if pendingAreaDeletion.listCount > 0 {
            return "The selected folder\(pendingAreaDeletion.folderCount == 1 ? "" : "s") contain \(listDescription). Choose whether to move contents to root or delete them."
        }

        return "The selected folder\(pendingAreaDeletion.folderCount == 1 ? "" : "s") contain \(nestedDescription). Choose whether to move contents to root or delete them."
    }

    private var sidebarWithPresentations: some View {
        sidebarList
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(isPresented: $showNewListSheet)
        }
        .sheet(isPresented: $showIconPickerSheet, onDismiss: {
            iconPickerList = nil
        }) {
            if let list = iconPickerList {
                SFSymbolPicker(selectedSymbol: Binding(
                    get: { list.icon },
                    set: { newIcon in
                        list.icon = newIcon
                        list.updatedAt = Date()
                        try? modelContext.save()
                    }
                ))
            } else {
                EmptyView()
            }
        }
        .alert("Rename List", isPresented: $showRenameAlert) {
            TextField("Name", text: $editingName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let list = editingList, !trimmedEditingName.isEmpty {
                    list.name = trimmedEditingName
                    list.updatedAt = Date()
                    try? modelContext.save()
                }
            }
        }
        .alert("Rename Folder", isPresented: $showAreaRenameAlert) {
            TextField("Name", text: $editingAreaName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let area = editingArea, !trimmedEditingAreaName.isEmpty {
                    area.name = trimmedEditingAreaName
                    try? modelContext.save()
                }
            }
        }
        .sheet(isPresented: $showNewAreaSheet) {
            NewAreaSheet(isPresented: $showNewAreaSheet)
        }
        .sheet(isPresented: $showNewTagSheet) {
            TagDetailSheet(isPresented: $showNewTagSheet, tagToEdit: nil)
        }
        .sheet(item: $editingTag) { tag in
            TagDetailSheet(
                isPresented: Binding(
                    get: { true },
                    set: { _ in editingTag = nil }
                ),
                tagToEdit: tag
            )
        }
    }

    private var sidebarWithDeleteDialog: some View {
        sidebarWithPresentations
        .confirmationDialog(
            areaDeleteDialogTitle,
            isPresented: $showAreaDeleteContentsPrompt,
            titleVisibility: .visible
        ) {
            Button("Move Contents to Root") {
                executePendingAreaDeletion(moveContentsToRoot: true)
            }
            Button("Delete Folders and Contents", role: .destructive) {
                executePendingAreaDeletion(moveContentsToRoot: false)
            }
            Button("Cancel", role: .cancel) {
                pendingAreaDeletion = nil
            }
        } message: {
            Text(areaDeleteDialogMessage)
        }
    }

    private var sidebarWithSelectionSync: some View {
        sidebarWithDeleteDialog
        .onAppear {
            syncSelectionFromBindings()
            enforceWikiHopSelectionGuard()
        }
        .onChange(of: selectedList?.id) { _, _ in
            syncSelectionFromBindings()
        }
        .onChange(of: selectedLabel?.id) { _, _ in
            syncSelectionFromBindings()
        }
        .onChange(of: selectedTag?.id) { _, _ in
            syncSelectionFromBindings()
        }
        .onChange(of: rootSelection) { _, _ in
            syncSelectionFromBindings()
        }
        .onChange(of: isWikiHopEnabled) { _, _ in
            enforceWikiHopSelectionGuard()
            syncSelectionFromBindings()
        }
        .onChange(of: isWikiHopPostV1Enabled) { _, _ in
            enforceWikiHopSelectionGuard()
            syncSelectionFromBindings()
        }
        .onChange(of: areas.map(\.id)) { _, currentAreaIDs in
            selectedAreaIDs.formIntersection(Set(currentAreaIDs))
        }
        .onChange(of: sidebarSelection) { _, newValue in
            guard let newValue else { return }
            applySelection(newValue)
        }
        .onChange(of: showAreaDeleteContentsPrompt) { _, isPresented in
            if !isPresented {
                pendingAreaDeletion = nil
            }
        }
    }

    var body: some View {
        sidebarWithSelectionSync
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewReadingList)) { _ in
            showNewListSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewFolder)) { _ in
            showNewAreaSheet = true
        }
        .background {
            SidebarPaneBackground()
                .ignoresSafeArea(.container, edges: [.top, .bottom])
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarList: some View {
        List(selection: $sidebarSelection) {
            exploreSection
            listsSection
            labelsSection
            tagsSection
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .tint(.clear)
        .transaction { transaction in
            // Avoid style/layout flash while SwiftData-backed sidebar content hydrates.
            transaction.animation = nil
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isWikiHopAvailable)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDeleteCommand {
            guard !selectedAreaIDs.isEmpty else { return }
            requestAreaDeletion(for: selectedAreaIDs)
        }
    }

    private func sidebarSectionHeader<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            Text(title)
                .font(SidebarMetrics.sectionHeaderFont)
                .foregroundStyle(.tertiary)
                .textCase(nil)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: SidebarMetrics.sectionHeaderHeight, alignment: .leading)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        sidebarSectionHeader(title) { EmptyView() }
    }

    private func sidebarAddButton(action: @escaping () -> Void, help: String) -> some View {
        Button(action: action) {
            sidebarAccessoryGlyph("plus")
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func sidebarAccessoryGlyph(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: SidebarMetrics.itemFontSize, weight: .semibold))
            .imageScale(.medium)
            .foregroundStyle(.secondary)
            .frame(
                width: SidebarMetrics.trailingControlSize,
                height: SidebarMetrics.trailingControlSize,
                alignment: .center
            )
            .contentShape(Rectangle())
    }

    private func rootRowLabel(_ title: String, systemImage: String? = nil, isSelected: Bool = false) -> some View {
        SidebarRootRowLabel(
            title: title,
            systemImage: systemImage,
            isSelected: isSelected
        )
    }

    private func selectableRootItem(
        _ title: String,
        systemImage: String,
        selection: SidebarRootSelection
    ) -> some View {
        rootRowLabel(
            title,
            systemImage: systemImage,
            isSelected: resolvedSelection == .root(selection)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(SidebarMetrics.rowInsets)
        .onTapGesture {
            selectSidebarTarget(.root(selection))
        }
    }

    private func selectSidebarTarget(_ target: SidebarSelectionID) {
        applySelection(target)
        if sidebarSelection != target {
            sidebarSelection = target
        }
    }

    private func applySelection(_ selection: SidebarSelectionID) {
        if appState.showSearch {
            if case .search = selection {
                // keep search active
            } else {
                appState.showSearch = false
            }
        }

        switch selection {
        case .search:
            appState.startSearch(context: .navigation)
        case .area(let areaId):
            guard areas.contains(where: { $0.id == areaId }) else {
                setRecentsSelection()
                return
            }
            if !selectedAreaIDs.contains(areaId) {
                selectedAreaIDs = [areaId]
            }
        case .root(let root):
            selectedAreaIDs.removeAll()
            if root == .wikiHop && !isWikiHopAvailable {
                setRecentsSelection()
                return
            }

            selectedList = nil
            selectedLabel = nil
            selectedTag = nil
            rootSelection = root

            if root == .discover, discoverOpenMode == .readerPage {
                appState.showDiscoverPage()
            }
        case .list(let listId):
            selectedAreaIDs.removeAll()
            guard let list = lists.first(where: { $0.id == listId }) else {
                setRecentsSelection()
                return
            }
            selectedList = list
            selectedLabel = nil
            selectedTag = nil
            rootSelection = .recents
        case .label(let labelId):
            selectedAreaIDs.removeAll()
            guard let label = labels.first(where: { $0.id == labelId }) else {
                setRecentsSelection()
                return
            }
            selectedLabel = label
            selectedList = nil
            selectedTag = nil
            rootSelection = .recents
        case .tag(let tagId):
            selectedAreaIDs.removeAll()
            guard let tag = tags.first(where: { $0.id == tagId }) else {
                setRecentsSelection()
                return
            }
            selectedTag = tag
            selectedList = nil
            selectedLabel = nil
            rootSelection = .recents
        }
    }

    private func syncSelectionFromBindings() {
        let resolved = resolvedSelection
        guard sidebarSelection != resolved else { return }
        sidebarSelection = resolved
    }

    private func setRecentsSelection() {
        appState.showSearch = false
        selectedList = nil
        selectedLabel = nil
        selectedTag = nil
        selectedAreaIDs.removeAll()
        rootSelection = .recents
        let fallback: SidebarSelectionID = .root(.recents)
        if sidebarSelection != fallback {
            sidebarSelection = fallback
        }
    }

    private func enforceWikiHopSelectionGuard() {
        guard !isWikiHopAvailable else { return }
        guard rootSelection == .wikiHop else { return }
        setRecentsSelection()
    }
    
    // MARK: - Sections

    @ViewBuilder
    private var exploreSection: some View {
        Section {
            selectableRootItem("Discover", systemImage: "sparkles", selection: .discover)

            rootRowLabel(
                "Search",
                systemImage: "magnifyingglass",
                isSelected: appState.showSearch
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(SidebarMetrics.rowInsets)
            .disabled(appState.isWikiHopNavigationLocked)
            .onTapGesture {
                guard !appState.isWikiHopNavigationLocked else { return }
                selectSidebarTarget(.search)
            }

            selectableRootItem("Recents", systemImage: "clock", selection: .recents)

            if isWikiHopAvailable {
                selectableRootItem("Wiki-Hop", systemImage: "figure.walk", selection: .wikiHop)
            }
        } header: {
            sidebarSectionHeader("Explore")
        }
    }
    
    @ViewBuilder
    private var listsSection: some View {
        Section {
            // Root-level lists (not in any area)
            if rootLevelLists.isEmpty && rootAreas.isEmpty {
                Text("No lists")
                    .foregroundStyle(.secondary)
                    .font(SidebarMetrics.itemFont)
                    .padding(.vertical, SidebarMetrics.emptyStateVerticalPadding)
                    .listRowInsets(SidebarMetrics.rowInsets)
            } else {
                // Show areas with their lists (recursive)
                ForEach(rootAreas) { area in
                    AreaRowView(
                        area: area,
                        lists: listsInArea(area),
                        childAreas: childAreas(of: area),
                        allAreas: areas,
                        selectedList: $selectedList,
                        selectedAreaIDs: $selectedAreaIDs,
                        sidebarSelection: $sidebarSelection,
                        listRow: listRow,
                        listsInArea: listsInArea,
                        childAreasOf: childAreas,
                        onRename: { areaToRename in
                            editingArea = areaToRename
                            editingAreaName = areaToRename.name
                            showAreaRenameAlert = true
                        },
                        onRequestDelete: { areaIDs in
                            requestAreaDeletion(for: areaIDs)
                        },
                        onCollapseHidingSelectedList: {
                            setRecentsSelection()
                        }
                    )
                }
                
                // Root-level lists
                ForEach(rootLevelLists) { list in
                    listRow(for: list)
                }
                .onMove(perform: moveList)
            }
        } header: {
            sidebarSectionHeader("Lists") {
                Menu {
                    Button("New List") {
                        showNewListSheet = true
                    }
                    Button("New Folder") {
                        showNewAreaSheet = true
                    }
                    Divider()
                    Picker("Sort", selection: $sortOrder) {
                        ForEach(ListSortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    Divider()
                    Picker("Density", selection: $sidebarDensityPreset) {
                        ForEach(SidebarDensityPreset.allCases, id: \.self) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                } label: {
                    sidebarAccessoryGlyph("plus")
                        .accessibilityIdentifier("lists-options-menu")
                        .accessibilityLabel("Lists Options Menu")
                }
                .menuStyle(.borderlessButton)
                .help("List Options")
                .accessibilityIdentifier("lists-options-menu")
            }
        }
    }
    
    @ViewBuilder
    private var labelsSection: some View {
        Section {
            if labels.isEmpty {
                Text("No labels")
                    .foregroundStyle(.secondary)
                    .font(SidebarMetrics.itemFont)
                    .padding(.vertical, SidebarMetrics.emptyStateVerticalPadding)
                    .listRowInsets(SidebarMetrics.rowInsets)
            } else {
                ForEach(sortedLabels) { label in
                    LabelRowView(
                        label: label,
                        isSelected: sidebarSelection == .label(label.id),
                        articleCount: labelArticleCounts[label.id] ?? 0,
                        onRename: {
                            onEditLabel(label)
                        },
                        onDelete: {
                            // Clear labelId from all articles with this label
                            let targetLabelId = label.id
                            let descriptor = FetchDescriptor<SavedArticle>(
                                predicate: #Predicate { $0.labelId == targetLabelId }
                            )
                            if let articles = try? modelContext.fetch(descriptor) {
                                for article in articles {
                                    article.labelId = nil
                                }
                            }
                            if selectedLabel?.id == label.id {
                                setRecentsSelection()
                            }
                            modelContext.delete(label)
                            try? modelContext.save()
                        }
                    )
                    .tag(SidebarSelectionID.label(label.id))
                }
                .onMove(perform: moveLabel)
            }
        } header: {
            sidebarSectionHeader("Labels") {
                sidebarAddButton(action: onAddNewLabel, help: "New Label")
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        Section {
            if tags.isEmpty {
                Text("No tags")
                    .foregroundStyle(.secondary)
                    .font(SidebarMetrics.itemFont)
                    .padding(.vertical, SidebarMetrics.emptyStateVerticalPadding)
                    .listRowInsets(SidebarMetrics.rowInsets)
            } else {
                ForEach(sortedTags) { tag in
                    TagRowView(
                        tag: tag,
                        isSelected: sidebarSelection == .tag(tag.id),
                        articleCount: tagArticleCounts[tag.id] ?? 0,
                        onRename: {
                            editingTag = tag
                        },
                        onDelete: {
                            if selectedTag?.id == tag.id {
                                setRecentsSelection()
                            }
                            modelContext.delete(tag)
                            try? modelContext.save()
                        }
                    )
                    .tag(SidebarSelectionID.tag(tag.id))
                }
                .onMove(perform: moveTag)
            }
        } header: {
            sidebarSectionHeader("Tags") {
                sidebarAddButton(
                    action: { showNewTagSheet = true },
                    help: "New Tag"
                )
            }
        }
    }

    // MARK: - Helper Views
    
    @ViewBuilder
    private func listRow(for list: ReadingList) -> some View {
        ListRowView(
            list: list,
            isSelected: sidebarSelection == .list(list.id),
            onRename: {
                editingList = list
                editingName = list.name
                showRenameAlert = true
            },
            onChangeIcon: {
                iconPickerList = list
                showIconPickerSheet = true
            },
            onDelete: {
                withAnimation {
                    if selectedList?.id == list.id {
                        setRecentsSelection()
                    }
                    modelContext.delete(list)
                    try? modelContext.save()
                }
            }
        )
        .tag(SidebarSelectionID.list(list.id))
        .draggable(list.id.uuidString) {
            SwiftUI.Label(list.name, systemImage: list.icon)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, location in
            guard let idString = items.first,
                  let uuid = UUID(uuidString: idString) else { return false }
            
            // Find the list being dragged
            let descriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == uuid })
            if let list = try? modelContext.fetch(descriptor).first {
                // Move to root
                list.areaId = nil
                try? modelContext.save()
                return true
            }
            return false
        }
    }
    
    // MARK: - Actions

    private func requestAreaDeletion(for requestedAreaIDs: Set<UUID>) {
        guard let pending = buildPendingAreaDeletion(from: requestedAreaIDs) else { return }

        if pending.hasContents {
            pendingAreaDeletion = pending
            showAreaDeleteContentsPrompt = true
            return
        }

        deleteAreasOnly(rootAreaIDs: pending.rootAreaIDs)
    }

    private func executePendingAreaDeletion(moveContentsToRoot: Bool) {
        guard let pending = pendingAreaDeletion else { return }
        pendingAreaDeletion = nil
        showAreaDeleteContentsPrompt = false

        if moveContentsToRoot {
            deleteAreasMovingContentsToRoot(rootAreaIDs: pending.rootAreaIDs)
        } else {
            deleteAreasAndContents(rootAreaIDs: pending.rootAreaIDs)
        }
    }

    private func buildPendingAreaDeletion(from requestedAreaIDs: Set<UUID>) -> PendingAreaDeletion? {
        let existingIDs = Set(areas.map(\.id))
        let validAreaIDs = requestedAreaIDs.intersection(existingIDs)
        guard !validAreaIDs.isEmpty else { return nil }

        let rootAreaIDs = topLevelAreaIDs(from: validAreaIDs)
        guard !rootAreaIDs.isEmpty else { return nil }

        var subtreeAreaIDs: Set<UUID> = []
        for areaID in rootAreaIDs {
            subtreeAreaIDs.formUnion(areaSubtreeIDs(for: areaID))
        }

        let listCount = lists.reduce(into: 0) { count, list in
            guard let areaID = list.areaId, subtreeAreaIDs.contains(areaID) else { return }
            count += 1
        }
        let nestedFolderCount = max(0, subtreeAreaIDs.count - rootAreaIDs.count)

        return PendingAreaDeletion(
            rootAreaIDs: rootAreaIDs,
            folderCount: rootAreaIDs.count,
            listCount: listCount,
            nestedFolderCount: nestedFolderCount
        )
    }

    private func topLevelAreaIDs(from candidateIDs: Set<UUID>) -> [UUID] {
        let index = areaIndexByID
        let sorted = candidateIDs.sorted(by: compareAreasForSortOrderByID(index: index))
        return sorted.filter { areaID in
            var currentParentID = index[areaID]?.parentId
            while let parentID = currentParentID {
                if candidateIDs.contains(parentID) {
                    return false
                }
                currentParentID = index[parentID]?.parentId
            }
            return true
        }
    }

    private func compareAreasForSortOrderByID(index: [UUID: Area]) -> (UUID, UUID) -> Bool {
        { lhsID, rhsID in
            guard let lhs = index[lhsID], let rhs = index[rhsID] else {
                return lhsID.uuidString < rhsID.uuidString
            }
            return compareAreasForSortOrder(lhs, rhs)
        }
    }

    private func areaSubtreeIDs(for rootAreaID: UUID) -> Set<UUID> {
        var visited: Set<UUID> = [rootAreaID]
        var queue: [UUID] = [rootAreaID]

        while let current = queue.popLast() {
            for area in areas where area.parentId == current {
                if visited.insert(area.id).inserted {
                    queue.append(area.id)
                }
            }
        }

        return visited
    }

    private func areaDepth(for areaID: UUID, depthCache: inout [UUID: Int]) -> Int {
        if let cachedDepth = depthCache[areaID] {
            return cachedDepth
        }

        guard let area = areaIndexByID[areaID], let parentID = area.parentId else {
            depthCache[areaID] = 0
            return 0
        }

        let depth = areaDepth(for: parentID, depthCache: &depthCache) + 1
        depthCache[areaID] = depth
        return depth
    }

    private func deleteAreasOnly(rootAreaIDs: [UUID]) {
        let rootSet = Set(rootAreaIDs)
        for area in areas where area.parentId.map(rootSet.contains) == true {
            area.parentId = nil
        }
        for list in lists where list.areaId.map(rootSet.contains) == true {
            list.areaId = nil
            list.updatedAt = Date()
        }
        for areaID in rootAreaIDs {
            if let area = areaIndexByID[areaID] {
                modelContext.delete(area)
            }
        }
        try? modelContext.save()
        selectedAreaIDs.subtract(rootSet)
    }

    private func deleteAreasMovingContentsToRoot(rootAreaIDs: [UUID]) {
        deleteAreasOnly(rootAreaIDs: rootAreaIDs)
    }

    private func deleteAreasAndContents(rootAreaIDs: [UUID]) {
        var subtreeAreaIDs: Set<UUID> = []
        for rootAreaID in rootAreaIDs {
            subtreeAreaIDs.formUnion(areaSubtreeIDs(for: rootAreaID))
        }

        if let selectedList, let selectedListAreaID = selectedList.areaId, subtreeAreaIDs.contains(selectedListAreaID) {
            setRecentsSelection()
        }

        for list in lists where list.areaId.map(subtreeAreaIDs.contains) == true {
            modelContext.delete(list)
        }

        var depthCache: [UUID: Int] = [:]
        let areasToDelete = areas
            .filter { subtreeAreaIDs.contains($0.id) }
            .sorted { lhs, rhs in
                areaDepth(for: lhs.id, depthCache: &depthCache) > areaDepth(for: rhs.id, depthCache: &depthCache)
            }

        for area in areasToDelete {
            modelContext.delete(area)
        }

        try? modelContext.save()
        selectedAreaIDs.subtract(subtreeAreaIDs)
    }
    
    private func moveList(from source: IndexSet, to destination: Int) {
        // When using manual sort, update sortOrder values
        var orderedLists = rootLevelLists
        orderedLists.move(fromOffsets: source, toOffset: destination)
        
        // Update sortOrder for all lists
        for (index, list) in orderedLists.enumerated() {
            list.sortOrder = index
        }
        
        // Switch to manual sort to preserve order
        sortOrder = .manual
        try? modelContext.save()
    }
    
    private func moveLabel(from source: IndexSet, to destination: Int) {
        var updatedLabels = sortedLabels
        updatedLabels.move(fromOffsets: source, toOffset: destination)
        
        // Update sort order
        for (index, label) in updatedLabels.enumerated() {
            label.sortOrder = index
        }
        try? modelContext.save()
    }

    private func moveTag(from source: IndexSet, to destination: Int) {
        var updatedTags = sortedTags
        updatedTags.move(fromOffsets: source, toOffset: destination)

        for (index, tag) in updatedTags.enumerated() {
            tag.sortOrder = index
        }
        try? modelContext.save()
    }
}


/// Native macOS sidebar row - HIG compliant
/// References: Finder, Notes, Craft sidebars
private struct SidebarRootRowLabel: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let systemImage: String?
    let isSelected: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(SidebarMetrics.itemIconFont.weight(.semibold))
                    .foregroundStyle(
                        SidebarMetrics.iconColor(
                            for: colorScheme,
                            isSelected: isSelected,
                            isHovered: isHovered
                        )
                    )
                    .frame(width: SidebarMetrics.itemIconWidth, alignment: .center)
            }

            Text(title)
                .font(SidebarMetrics.itemFont)
                .foregroundStyle(SidebarMetrics.titleColor(for: colorScheme, isSelected: isSelected))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinimumHitHeight, alignment: .leading)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .listRowBackground(SidebarRowSurface(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Native macOS sidebar row - HIG compliant
/// References: Finder, Notes, Craft sidebars
private struct ListRowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let list: ReadingList
    let isSelected: Bool
    let onRename: () -> Void
    let onChangeIcon: () -> Void
    let onDelete: () -> Void

    @State private var isArticleDropTargeted = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            Image(systemName: list.icon)
                .symbolVariant(isSelected ? .fill : .none)
                .font(SidebarMetrics.itemIconFont.weight(.semibold))
                .foregroundStyle(
                    SidebarMetrics.iconColor(
                        for: colorScheme,
                        isSelected: isSelected,
                        isHovered: isHovered
                    )
                )
                .frame(width: SidebarMetrics.itemIconWidth, alignment: .center)

            Text(list.name)
                .font(SidebarMetrics.itemFont)
                .foregroundStyle(SidebarMetrics.titleColor(for: colorScheme, isSelected: isSelected))
                .lineLimit(1)

            Spacer(minLength: 0)

            if list.articles.count > 0 {
                SidebarCountBadge(count: list.articles.count, isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinimumHitHeight, alignment: .leading)
        .background(
            Color.clear
        )
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .listRowInsets(SidebarMetrics.rowInsets)
        .listRowBackground(
            SidebarRowSurface(
                isSelected: isSelected,
                isHovered: isHovered,
                isDropTarget: isArticleDropTargeted
            )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onRename()
            } label: {
                SwiftUI.Label("Rename", systemImage: "pencil")
            }

            Button {
                onChangeIcon()
            } label: {
                SwiftUI.Label("Change Icon", systemImage: "photo")
            }

            Divider()

            Button("Delete", role: .destructive, action: onDelete)
        }
        // Accept dropped articles
        .dropDestination(for: String.self) { items, _ in
            handleDrop(items: items)
        } isTargeted: { targeted in
            isArticleDropTargeted = targeted
        }
    }
    
    private func handleDrop(items: [String]) -> Bool {
        guard let idString = items.first,
              let uuid = UUID(uuidString: idString) else { return false }

        // Find the article being dragged
        let descriptor = FetchDescriptor<SavedArticle>(predicate: #Predicate { $0.id == uuid })
        guard let savedArticle = try? modelContext.fetch(descriptor).first else { return false }

        // Don't drop onto same list
        guard savedArticle.readingList?.id != list.id else { return false }

        // Move article: create copy in target list
        let newArticle = SavedArticle(
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            extract: savedArticle.extract,
            thumbnailURL: savedArticle.thumbnailURL,
            list: list
        )
        newArticle.isRead = savedArticle.isRead
        newArticle.labelId = savedArticle.labelId // Preserve label
        list.articles.append(newArticle)
        list.updatedAt = Date()

        // Remove from source list
        if let sourceList = savedArticle.readingList {
            sourceList.articles.removeAll { $0.id == savedArticle.id }
            sourceList.updatedAt = Date()
        }
        modelContext.delete(savedArticle)

        try? modelContext.save()
        return true
    }
}

/// Label row for sidebar - displays colored circle and name
private struct LabelRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let label: Label
    let isSelected: Bool
    let articleCount: Int
    let onRename: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.modelContext) private var modelContext
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            Circle()
                .fill(label.color.swiftUIColor)
                .frame(width: 8, height: 8)
                .frame(width: SidebarMetrics.itemIconWidth, alignment: .center)

            Text(label.name)
                .font(SidebarMetrics.itemFont)
                .foregroundStyle(SidebarMetrics.titleColor(for: colorScheme, isSelected: isSelected))
                .lineLimit(1)

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount, isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinimumHitHeight, alignment: .leading)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .listRowInsets(SidebarMetrics.rowInsets)
        .listRowBackground(SidebarRowSurface(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            labelContextMenu
        }
    }

    @ViewBuilder
    private var labelContextMenu: some View {
        Button {
            onRename()
        } label: {
            SwiftUI.Label("Rename", systemImage: "pencil")
        }

        Menu {
            colorSelectionItems
        } label: {
            SwiftUI.Label("Change Color", systemImage: "paintpalette")
        }

        Divider()

        Button(role: .destructive) {
            onDelete()
        } label: {
            SwiftUI.Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private var colorSelectionItems: some View {
        SwiftUI.ForEach(LabelColor.allCases, id: \.self) { (color: LabelColor) in
            Button {
                label.color = color
                try? modelContext.save()
            } label: {
                SwiftUI.Label {
                    Text(color.rawValue)
                } icon: {
                    Image(systemName: label.color == color ? "checkmark.circle.fill" : "circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(label.color == color ? Color.white : color.swiftUIColor, color.swiftUIColor)
                }
            }
        }
    }
}

private struct TagRowView: View {
    @Environment(\.colorScheme) private var colorScheme

    let tag: Tag
    let isSelected: Bool
    let articleCount: Int
    let onRename: () -> Void
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: SidebarMetrics.rowSpacing) {
            Image(systemName: "tag")
                .symbolVariant(isSelected ? .fill : .none)
                .font(SidebarMetrics.itemIconFont)
                .foregroundStyle(
                    SidebarMetrics.iconColor(
                        for: colorScheme,
                        isSelected: isSelected,
                        isHovered: isHovered
                    )
                )
                .frame(width: SidebarMetrics.itemIconWidth, alignment: .center)

            Text(tag.name)
                .font(SidebarMetrics.itemFont)
                .foregroundStyle(SidebarMetrics.titleColor(for: colorScheme, isSelected: isSelected))
                .lineLimit(1)

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount, isSelected: isSelected)
            }
        }
        .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinimumHitHeight, alignment: .leading)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        .listRowInsets(SidebarMetrics.rowInsets)
        .listRowBackground(SidebarRowSurface(isSelected: isSelected, isHovered: isHovered))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button {
                onRename()
            } label: {
                SwiftUI.Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                SwiftUI.Label("Delete", systemImage: "trash")
            }
        }
    }
}

private struct SidebarCountBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    let count: Int
    var isSelected: Bool = false

    var body: some View {
        Text("\(count)")
            .font(SidebarMetrics.itemFont)
            .foregroundStyle(SidebarMetrics.countColor(for: colorScheme, isSelected: isSelected))
            .monospacedDigit()
            .frame(minWidth: 22, alignment: .trailing)
    }
}



/// Collapsible area/folder row with drop-to-add support and nested areas
private struct AreaRowView<ListRow: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    let area: Area
    let lists: [ReadingList]
    let childAreas: [Area]
    let allAreas: [Area]
    @Binding var selectedList: ReadingList?
    @Binding var selectedAreaIDs: Set<UUID>
    @Binding var sidebarSelection: SidebarSelectionID?
    let listRow: (ReadingList) -> ListRow
    let listsInArea: (Area) -> [ReadingList]
    let childAreasOf: (Area) -> [Area]
    let onRename: (Area) -> Void
    let onRequestDelete: (Set<UUID>) -> Void
    let onCollapseHidingSelectedList: () -> Void

    @State private var isTargeted = false
    @State private var isHovered = false

    private var deleteTargetAreaIDs: Set<UUID> {
        if selectedAreaIDs.contains(area.id) && selectedAreaIDs.count > 1 {
            return selectedAreaIDs
        }
        return [area.id]
    }

    private var deleteActionLabel: String {
        deleteTargetAreaIDs.count > 1 ? "Delete Selected Folders" : "Delete Folder"
    }

    private var isSelected: Bool {
        sidebarSelection == .area(area.id)
    }

    /// Total count of lists in this area and all nested areas
    private var totalListCount: Int {
        lists.count + childAreas.reduce(0) { $0 + countListsRecursive(in: $1) }
    }

    private func countListsRecursive(in area: Area) -> Int {
        let directLists = listsInArea(area).count
        let nestedLists = childAreasOf(area).reduce(0) { $0 + countListsRecursive(in: $1) }
        return directLists + nestedLists
    }

    private var parentAreaByID: [UUID: UUID?] {
        Dictionary(uniqueKeysWithValues: allAreas.map { ($0.id, $0.parentId) })
    }

    private var collapseWouldHideSelectedList: Bool {
        SidebarCollapseSelectionGuard.collapseWouldHideSelectedList(
            selectedAreaID: selectedList?.areaId,
            collapsingAreaID: area.id,
            parentAreaByID: parentAreaByID
        )
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { area.isExpanded },
            set: { newValue in
                if !newValue && collapseWouldHideSelectedList {
                    // Keep sidebar selection anchored to a visible row before hiding
                    // the active list inside a collapsing folder subtree.
                    onCollapseHidingSelectedList()
                }
                if reduceMotion {
                    area.isExpanded = newValue
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        area.isExpanded = newValue
                    }
                }
                try? modelContext.save()
            }
        )) {
            // Nested child areas first
            ForEach(childAreas) { childArea in
                AreaRowView(
                    area: childArea,
                    lists: listsInArea(childArea),
                    childAreas: childAreasOf(childArea),
                    allAreas: allAreas,
                    selectedList: $selectedList,
                    selectedAreaIDs: $selectedAreaIDs,
                    sidebarSelection: $sidebarSelection,
                    listRow: listRow,
                    listsInArea: listsInArea,
                    childAreasOf: childAreasOf,
                    onRename: onRename,
                    onRequestDelete: onRequestDelete,
                    onCollapseHidingSelectedList: onCollapseHidingSelectedList
                )
            }

            // Lists in this area
            ForEach(lists) { list in
                listRow(list)
            }
        } label: {
            HStack(spacing: SidebarMetrics.rowSpacing) {
                Image(systemName: area.icon)
                    .symbolVariant(isSelected ? .fill : .none)
                    .font(SidebarMetrics.itemIconFont)
                    .foregroundStyle(
                        isTargeted
                            ? Color.accentColor
                            : SidebarMetrics.iconColor(
                                for: colorScheme,
                                isSelected: isSelected,
                                isHovered: isHovered
                            )
                    )
                    .frame(width: SidebarMetrics.itemIconWidth, alignment: .center)
                Text(area.name)
                    .font(SidebarMetrics.itemFont)
                    .foregroundStyle(SidebarMetrics.titleColor(for: colorScheme, isSelected: isSelected))

                Spacer()

                // Total list count badge (including nested)
                if totalListCount > 0 {
                    SidebarCountBadge(count: totalListCount, isSelected: isSelected)
                }
            }
            .frame(maxWidth: .infinity, minHeight: SidebarMetrics.rowMinimumHitHeight, alignment: .leading)
            .background(Color.clear)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isTargeted)
            .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.rowCornerRadius, style: .continuous))
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if SystemBridge.isCommandPressed {
                    if selectedAreaIDs.contains(area.id) {
                        selectedAreaIDs.remove(area.id)
                        if let remaining = selectedAreaIDs.sorted(by: { $0.uuidString < $1.uuidString }).first {
                            sidebarSelection = .area(remaining)
                        } else {
                            sidebarSelection = nil
                        }
                    } else {
                        selectedAreaIDs.insert(area.id)
                        sidebarSelection = .area(area.id)
                    }
                } else {
                    selectedAreaIDs = [area.id]
                    sidebarSelection = .area(area.id)
                }
            }
        )
        .tag(SidebarSelectionID.area(area.id))
        .listRowInsets(SidebarMetrics.rowInsets)
        .listRowBackground(
            SidebarRowSurface(
                isSelected: isSelected,
                isHovered: isHovered,
                isDropTarget: isTargeted
            )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel(area.name)
        .accessibilityValue(totalListCount > 0 ? "\(totalListCount) lists" : "Empty folder")
        .accessibilityIdentifier("area-row-\(area.name)")
        .contextMenu {
            Button {
                onRename(area)
            } label: {
                SwiftUI.Label("Rename", systemImage: "pencil")
            }

            Divider()

            Button(role: .destructive) {
                onRequestDelete(deleteTargetAreaIDs)
            } label: {
                SwiftUI.Label(deleteActionLabel, systemImage: "trash")
            }
        }
        .draggable(area.id.uuidString) {
            SwiftUI.Label(area.name, systemImage: area.icon)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let idString = items.first,
                  let uuid = UUID(uuidString: idString) else { return false }

            // Try to find as ReadingList first
            let listDescriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == uuid })
            if let list = try? modelContext.fetch(listDescriptor).first {
                list.areaId = area.id
                try? modelContext.save()
                return true
            }

            // Try to find as Area (for nesting areas)
            let areaDescriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == uuid })
            if let draggedArea = try? modelContext.fetch(areaDescriptor).first {
                // Prevent dropping area into itself or its descendants
                guard draggedArea.id != area.id else { return false }
                guard !isDescendant(area, of: draggedArea) else { return false }

                draggedArea.parentId = area.id
                try? modelContext.save()
                return true
            }

            return false
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    /// Check if potentialDescendant is a descendant of potentialAncestor
    private func isDescendant(_ potentialDescendant: Area, of potentialAncestor: Area) -> Bool {
        var current: Area? = potentialDescendant
        while let check = current {
            if check.id == potentialAncestor.id {
                return true
            }
            // Find parent area
            current = allAreas.first { $0.id == check.parentId }
        }
        return false
    }

}
