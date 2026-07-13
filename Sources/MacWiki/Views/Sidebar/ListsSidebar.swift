import SwiftUI
import SwiftData

enum SidebarSelectionID: Hashable {
    case search
    case root(SidebarRootSelection)
    case list(UUID)
    case label(UUID)
    case tag(UUID)
    case area(UUID)

    var accessibilityIdentifier: String {
        switch self {
        case .search:
            return "sidebar-row-search"
        case .root(let selection):
            return "sidebar-row-root-\(selection.rawValue)"
        case .list(let id):
            return "sidebar-row-list-\(id.uuidString)"
        case .label(let id):
            return "sidebar-row-label-\(id.uuidString)"
        case .tag(let id):
            return "sidebar-row-tag-\(id.uuidString)"
        case .area(let id):
            return "sidebar-row-area-\(id.uuidString)"
        }
    }
}

/// Lists sidebar with reading lists management
struct ListsSidebar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Query private var lists: [ReadingList]
    @Query private var areas: [Area]
    @Query private var savedArticles: [SavedArticle]
    @Query(sort: \Highlight.createdAt, order: .reverse) private var highlights: [Highlight]
    @Query(sort: \ArticleState.updatedAt, order: .reverse) private var articleStates: [ArticleState]

    @Binding var selectedList: ReadingList?
    @Binding var selectedLabel: Label?
    @Binding var selectedTag: Tag?
    @Binding var rootSelection: SidebarRootSelection
    let sidebarSearchModel: SidebarSearchSurfaceModel
    @State private var showNewListSheet = false
    @State private var showNewAreaSheet = false
    @State private var sidebarSelectionSet: Set<SidebarSelectionID> = []
    @State private var topObscuredHeight: CGFloat = 38
    @State private var selectedAreaIDs: Set<UUID> = []
    @AppStorage(AppStorageKey.ListsSidebar.sortOrder) private var sortOrder: ListSortOrder = .updatedDate

    // Editing state for lists
    @State private var editingList: ReadingList?
    @State private var editingName: String = ""
    @State private var showRenameAlert = false
    @State private var iconPickerList: ReadingList?
    @AppStorage(AppStorageKey.Discover.openMode) private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var isWikiHopEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var isWikiHopPostV1Enabled = false

    // Editing state for areas
    @State private var editingArea: Area?
    @State private var editingAreaName: String = ""
    @State private var showAreaRenameAlert = false
    @State private var pendingAreaDeletion: ListsSidebarAreaDeletionPlan?
    @State private var showAreaDeleteContentsPrompt = false
    @State private var saveScheduler = DebouncedActionScheduler()

    // Tag management
    @State private var showNewTagSheet = false
    @State private var editingTag: Tag?

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    private var trimmedEditingAreaName: String {
        editingAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedSelectionSet: Set<SidebarSelectionID> {
        if appState.showSearch {
            return [.search]
        }
        if let listId = selectedList?.id {
            return [.list(listId)]
        }
        if let labelId = selectedLabel?.id {
            return [.label(labelId)]
        }
        if let tagId = selectedTag?.id {
            return [.tag(tagId)]
        }
        if !selectedAreaIDs.isEmpty {
            return Set(selectedAreaIDs.map(SidebarSelectionID.area))
        }
        if rootSelection == .wikiHop && !isWikiHopAvailable {
            return [.root(.recents)]
        }
        return [.root(rootSelection)]
    }

    private var isWikiHopAvailable: Bool {
        isWikiHopPostV1Enabled && isWikiHopEnabled
    }

    private var selectedAreaIDsKey: [UUID] {
        selectedAreaIDs.sorted(by: { $0.uuidString < $1.uuidString })
    }

    private var sidebarSections: [ListsSidebarTreeSection] {
        ListsSidebarTreeBuilder.build(
            snapshot: collectionsSnapshot,
            isWikiHopAvailable: isWikiHopAvailable
        )
    }

    private var collectionsSnapshot: ListsSidebarSnapshot {
        ListsSidebarSnapshot(
            lists: lists,
            areas: areas,
            labels: labels,
            tags: tags,
            savedArticles: savedArticles,
            highlights: highlights,
            articleStates: articleStates,
            sortOrder: sortOrder
        )
    }

    private var sortedLists: [ReadingList] {
        collectionsSnapshot.sortedLists
    }

    /// Lists not in any area
    private var rootLevelLists: [ReadingList] {
        collectionsSnapshot.rootLevelLists
    }

    /// Lists within a specific area
    private func listsInArea(_ area: Area) -> [ReadingList] {
        collectionsSnapshot.lists(in: area)
    }

    /// Root-level areas (not nested under another area)
    private var rootAreas: [Area] {
        collectionsSnapshot.rootAreas
    }

    /// Child areas within a specific parent area
    private func childAreas(of parent: Area) -> [Area] {
        collectionsSnapshot.childAreas(of: parent)
    }

    private var sortedLabels: [Label] {
        collectionsSnapshot.sortedLabels
    }

    private var sortedTags: [Tag] {
        collectionsSnapshot.sortedTags
    }

    private var labelArticleCounts: [UUID: Int] {
        collectionsSnapshot.labelArticleCounts
    }

    private var tagArticleCounts: [UUID: Int] {
        collectionsSnapshot.tagArticleCounts
    }

    private var areaIndexByID: [UUID: Area] {
        collectionsSnapshot.areaIndexByID
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

    private var plainSidebarTopInset: CGFloat {
        max(
            SidebarRowMetrics.nativeTopContentInset,
            max(0, topObscuredHeight) + SidebarRowMetrics.titlebarContentPadding
        )
    }

    private func saveModelContextNow() {
        guard modelContext.hasChanges else { return }
        modelContext.saveReportingFailure(operation: #function)
    }

    private func requestModelContextSave() {
        saveScheduler.schedule { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    private func flushScheduledModelContextSave() {
        saveScheduler.flush { [modelContext] in
            guard modelContext.hasChanges else { return }
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    private var sidebarWithPresentations: some View {
        sidebarList
        .sheet(isPresented: $showNewListSheet) {
            NewListSheet(isPresented: $showNewListSheet)
        }
        .sheet(item: $iconPickerList) { list in
            SFSymbolPicker(selectedSymbol: Binding(
                get: { list.icon },
                set: { newIcon in
                    list.icon = newIcon
                    list.updatedAt = Date()
                    requestModelContextSave()
                }
            ))
        }
        .alert("Rename List", isPresented: $showRenameAlert) {
            TextField("Name", text: $editingName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let list = editingList,
                   let normalizedName = ReadingListNamePolicy.normalized(editingName) {
                    list.name = normalizedName
                    list.updatedAt = Date()
                    modelContext.saveReportingFailure(operation: #function)
                }
            }
        }
        .alert("Rename Folder", isPresented: $showAreaRenameAlert) {
            TextField("Name", text: $editingAreaName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let area = editingArea, !trimmedEditingAreaName.isEmpty {
                    area.name = trimmedEditingAreaName
                    modelContext.saveReportingFailure(operation: #function)
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

    private var sidebarWithCollectionSnapshotSync: some View {
        sidebarWithDeleteDialog
            .onAppear {
                syncSelectionFromBindings()
                enforceWikiHopSelectionGuard()
            }
    }

    private var sidebarWithBindingSelectionSync: some View {
        sidebarWithCollectionSnapshotSync
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
            .onChange(of: appState.showSearch) { _, _ in
                syncSelectionFromBindings()
            }
            .onChange(of: selectedAreaIDsKey) { _, _ in
                syncSelectionFromBindings()
            }
    }

    private var sidebarWithSelectionSync: some View {
        sidebarWithBindingSelectionSync
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
            .onChange(of: sidebarSelectionSet) { oldValue, newValue in
                handleSidebarSelectionChange(from: oldValue, to: newValue)
            }
            .onChange(of: showAreaDeleteContentsPrompt) { _, isPresented in
                if !isPresented {
                    pendingAreaDeletion = nil
                }
            }
    }

    var body: some View {
        sidebarWithSelectionSync
        .onDisappear {
            flushScheduledModelContextSave()
        }
        .onChange(of: appState.newReadingListRequestID) { _, requestID in
            guard requestID != nil else { return }
            showNewListSheet = true
        }
        .onChange(of: appState.newFolderRequestID) { _, requestID in
            guard requestID != nil else { return }
            showNewAreaSheet = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarList: some View {
        GeometryReader { proxy in
            List {
                ForEach(sidebarSections) { section in
                    sidebarSectionView(section)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, plainSidebarTopInset, for: .scrollIndicators)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear
                    .frame(height: plainSidebarTopInset)
                    .allowsHitTesting(false)
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isWikiHopAvailable)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.clear)
            .environment(\.sidebarRowLayoutMetrics, SidebarRowLayoutMetrics(availableWidth: proxy.size.width))
            .onAppear {
                updateTopObscuredHeight(proxy.safeAreaInsets.top)
            }
            .onChange(of: proxy.safeAreaInsets.top) { _, newValue in
                updateTopObscuredHeight(newValue)
            }
        }
    }

    @ViewBuilder
    private func sidebarSectionView(_ section: ListsSidebarTreeSection) -> some View {
        switch section.kind {
        case .explore:
            Section {
                sidebarSearchButton

                ForEach(section.nodes) { node in
                    sidebarNodeView(node)
                }
            } header: {
                sidebarSectionHeader("Explore")
            }
        case .lists:
            Section {
                if !section.nodes.isEmpty {
                    ForEach(section.nodes) { node in
                        sidebarNodeView(node)
                    }
                }
            } header: {
                sidebarSectionHeader("Lists") {
                    sidebarLibraryMenu
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let uuid = UUID(uuidString: idString) else {
                    return false
                }
                return moveItemToRoot(uuid)
            }
        case .labels:
            Section {
                if section.nodes.isEmpty {
                    sidebarEmptyCollectionAction(
                        title: "New Label",
                        systemImage: "plus.circle",
                        identifier: "sidebar-new-label-empty",
                        action: onAddNewLabel
                    )
                } else {
                    ForEach(section.nodes) { node in
                        sidebarNodeView(node)
                    }
                }
            } header: {
                sidebarSectionHeader("Labels") {
                    sidebarHeaderIconButton(
                        systemImage: "plus",
                        help: "New Label",
                        action: onAddNewLabel
                    )
                }
            }
        case .tags:
            Section {
                if section.nodes.isEmpty {
                    sidebarEmptyCollectionAction(
                        title: "New Tag",
                        systemImage: "plus.circle",
                        identifier: "sidebar-new-tag-empty",
                        action: { showNewTagSheet = true }
                    )
                } else {
                    ForEach(section.nodes) { node in
                        sidebarNodeView(node)
                    }
                }
            } header: {
                sidebarSectionHeader("Tags") {
                    sidebarHeaderIconButton(
                        systemImage: "plus",
                        help: "New Tag",
                        action: { showNewTagSheet = true }
                    )
                }
            }
        }
    }

    private func sidebarSectionHeader<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        ListsSidebarSectionHeader(title, accessory: accessory)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        sidebarSectionHeader(title) { EmptyView() }
    }

    private func sidebarHeaderIconButton(
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            SidebarHeaderAccessoryIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func sidebarEmptyCollectionAction(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        SidebarEmptyCollectionButton(
            title: title,
            systemImage: systemImage,
            identifier: identifier,
            action: action
        )
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }

    private var sidebarLibraryMenu: some View {
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
        } label: {
            SidebarHeaderAccessoryIcon(systemImage: "plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .frame(
            width: SidebarRowMetrics.headerAccessorySize,
            height: SidebarRowMetrics.headerAccessorySize,
            alignment: .center
        )
        .contentShape(Rectangle())
        .help("New List or Folder")
        .accessibilityLabel("New List or Folder")
        .accessibilityIdentifier("sidebar-actions-menu")
    }

    private func rootRowLabel(_ title: String, systemImage: String? = nil) -> some View {
        SidebarRootRowLabel(title: title, systemImage: systemImage)
    }

    @ViewBuilder
    private func sidebarNodeView(_ node: ListsSidebarTreeNode) -> some View {
        switch node.kind {
        case .root(let selection):
            sidebarSelectableRow(
                selection: .root(selection),
                accessibilityLabel: rootTitle(for: selection),
                isSelected: sidebarSelectionSet.contains(.root(selection))
            ) {
                rootRowLabel(rootTitle(for: selection), systemImage: rootSystemImage(for: selection))
            }
        case .list(let list):
            listRow(for: list)
        case .label(let label):
            let selection = SidebarSelectionID.label(label.id)
            sidebarSelectableRow(
                selection: .label(label.id),
                accessibilityLabel: label.name,
                isSelected: sidebarSelectionSet.contains(selection)
            ) {
                LabelRowView(
                    label: label,
                    articleCount: labelArticleCounts[label.id] ?? 0,
                    onPersistChange: requestModelContextSave,
                    onRename: {
                        onEditLabel(label)
                    },
                    onDelete: {
                        deleteLabel(label.id)
                    },
                    onArticleDrop: { payload in
                        applyDroppedArticle(payload, label: label)
                    }
                )
            }
            .accessibilityRepresentation {
                SidebarCollectionAccessibilityButton(
                    title: label.name,
                    identifier: selection.accessibilityIdentifier,
                    isSelected: sidebarSelectionSet.contains(selection),
                    onPress: { selectSidebarSelection(selection) },
                    onRename: { onEditLabel(label) },
                    onDelete: { deleteLabel(label.id) },
                    onColorChange: { color in changeLabelColor(label.id, color: color) }
                )
            }
        case .tag(let tag):
            let selection = SidebarSelectionID.tag(tag.id)
            sidebarSelectableRow(
                selection: .tag(tag.id),
                accessibilityLabel: tag.name,
                isSelected: sidebarSelectionSet.contains(selection)
            ) {
                TagRowView(
                    tag: tag,
                    articleCount: tagArticleCounts[tag.id] ?? 0,
                    onRename: {
                        editingTag = tag
                    },
                    onDelete: {
                        deleteTag(tag.id)
                    },
                    onArticleDrop: { payload in
                        addDroppedArticle(payload, tag: tag)
                    }
                )
            }
            .accessibilityRepresentation {
                SidebarCollectionAccessibilityButton(
                    title: tag.name,
                    identifier: selection.accessibilityIdentifier,
                    isSelected: sidebarSelectionSet.contains(selection),
                    onPress: { selectSidebarSelection(selection) },
                    onRename: { editingTag = tag },
                    onDelete: { deleteTag(tag.id) }
                )
            }
        case .area(let area):
            AreaRowView(
                area: area,
                lists: listsInArea(area),
                childAreas: childAreas(of: area),
                parentAreaByID: collectionsSnapshot.parentAreaByID,
                selectedAreaIDs: $selectedAreaIDs,
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
                onExpansionChange: { areaToUpdate, isExpanded in
                    if !isExpanded,
                       SidebarCollapseSelectionGuard.collapseWouldHideSelectedList(
                           selectedAreaID: selectedList?.areaId,
                           collapsingAreaID: areaToUpdate.id,
                           parentAreaByID: collectionsSnapshot.parentAreaByID
                       ) {
                        setRecentsSelection()
                    }
                    setAreaExpanded(areaToUpdate.id, isExpanded)
                },
                onPersistChange: requestModelContextSave,
                isSelected: selectedAreaIDs.contains(area.id)
            )
        }
    }

    private var sidebarSearchButton: some View {
        sidebarSelectableRow(
            selection: .search,
            accessibilityLabel: "Search",
            isSelected: sidebarSelectionSet.contains(.search),
            isDisabled: appState.isWikiHopNavigationLocked
        ) {
            rootRowLabel("Search", systemImage: "magnifyingglass")
        }
    }

    private func sidebarSelectableRow<Content: View>(
        selection: SidebarSelectionID,
        accessibilityLabel: String,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder label: () -> Content
    ) -> some View {
        Button {
            guard !isDisabled else { return }
            selectSidebarSelection(selection)
        } label: {
            SidebarRowContainer(isSelected: isSelected) {
                label()
            }
        }
        .buttonStyle(.plain)
        .tag(selection)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier(selection.accessibilityIdentifier)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func rootTitle(for selection: SidebarRootSelection) -> String {
        switch selection {
        case .discover:
            return "Discover"
        case .recents:
            return "Recents"
        case .wikiHop:
            return "Wiki-Hop"
        }
    }

    private func rootSystemImage(for selection: SidebarRootSelection) -> String {
        switch selection {
        case .discover:
            return "sparkles"
        case .recents:
            return "clock"
        case .wikiHop:
            return "figure.walk"
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
            selectedList = nil
            selectedLabel = nil
            selectedTag = nil
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
        let resolved = resolvedSelectionSet
        guard sidebarSelectionSet != resolved else { return }
        sidebarSelectionSet = resolved
    }

    private func selectSidebarSelection(_ selection: SidebarSelectionID) {
        let previousSelectionSet = sidebarSelectionSet
        let newSelectionSet: Set<SidebarSelectionID> = [selection]

        if previousSelectionSet == newSelectionSet {
            applySelection(selection)
            return
        }

        sidebarSelectionSet = newSelectionSet
    }

    private func setRecentsSelection() {
        appState.showSearch = false
        selectedList = nil
        selectedLabel = nil
        selectedTag = nil
        selectedAreaIDs.removeAll()
        rootSelection = .recents
        let fallback: Set<SidebarSelectionID> = [.root(.recents)]
        if sidebarSelectionSet != fallback {
            sidebarSelectionSet = fallback
        }
    }

    private func handleSidebarSelectionChange(
        from oldValue: Set<SidebarSelectionID>,
        to newValue: Set<SidebarSelectionID>
    ) {
        guard !newValue.isEmpty else {
            syncSelectionFromBindings()
            return
        }

        let addedSelections = newValue.subtracting(oldValue)
        let nonAreaSelections = newValue.filter {
            if case .area = $0 { return false }
            return true
        }

        if let selection = preferredSelection(in: Set(nonAreaSelections), preferring: addedSelections) {
            selectedAreaIDs.removeAll()
            applySelection(selection)
            let canonical: Set<SidebarSelectionID> = [selection]
            if sidebarSelectionSet != canonical {
                sidebarSelectionSet = canonical
            }
            return
        }

        let areaIDs = Set(newValue.compactMap { selection -> UUID? in
            if case .area(let areaID) = selection {
                return areaID
            }
            return nil
        })

        guard !areaIDs.isEmpty else {
            syncSelectionFromBindings()
            return
        }

        appState.showSearch = false
        selectedList = nil
        selectedLabel = nil
        selectedTag = nil
        selectedAreaIDs = areaIDs

        let canonical = Set(areaIDs.map(SidebarSelectionID.area))
        if sidebarSelectionSet != canonical {
            sidebarSelectionSet = canonical
        }
    }

    private func preferredSelection(
        in selections: Set<SidebarSelectionID>,
        preferring addedSelections: Set<SidebarSelectionID>
    ) -> SidebarSelectionID? {
        let preferredSelections = addedSelections
            .intersection(selections)
            .sorted(by: compareSidebarSelections(_:_:))
        if let preferred = preferredSelections.first {
            return preferred
        }
        return selections.sorted(by: compareSidebarSelections(_:_:)).first
    }

    private func compareSidebarSelections(_ lhs: SidebarSelectionID, _ rhs: SidebarSelectionID) -> Bool {
        sidebarSelectionSortKey(lhs) < sidebarSelectionSortKey(rhs)
    }

    private func sidebarSelectionSortKey(_ selection: SidebarSelectionID) -> String {
        switch selection {
        case .search:
            return "0-search"
        case .root(let root):
            return "1-root-\(rootTitle(for: root))"
        case .list(let id):
            return "2-list-\(id.uuidString)"
        case .label(let id):
            return "3-label-\(id.uuidString)"
        case .tag(let id):
            return "4-tag-\(id.uuidString)"
        case .area(let id):
            return "5-area-\(id.uuidString)"
        }
    }

    private func updateTopObscuredHeight(_ proposedHeight: CGFloat) {
        let resolved = max(0, proposedHeight)
        guard abs(topObscuredHeight - resolved) > 0.5 else { return }
        DispatchQueue.main.async {
            guard abs(topObscuredHeight - resolved) > 0.5 else { return }
            topObscuredHeight = resolved
        }
    }

    private func enforceWikiHopSelectionGuard() {
        guard !isWikiHopAvailable else { return }
        guard rootSelection == .wikiHop else { return }
        setRecentsSelection()
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func listRow(for list: ReadingList) -> some View {
        sidebarSelectableRow(
            selection: .list(list.id),
            accessibilityLabel: list.name,
            isSelected: sidebarSelectionSet.contains(.list(list.id))
        ) {
            ListRowView(
                list: list,
                onRename: {
                    editingList = list
                    editingName = list.name
                    showRenameAlert = true
                },
                onChangeIcon: {
                    iconPickerList = list
                },
                availableAreas: areas.sorted {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                onMoveToFolder: { targetAreaID in
                    moveList(list, toArea: targetAreaID)
                },
                onDelete: {
                    withAnimation {
                        if selectedList?.id == list.id {
                            setRecentsSelection()
                        }
                        modelContext.delete(list)
                        saveModelContextNow()
                    }
                },
                onArticleDrop: { payload in
                    moveDroppedArticle(payload, to: list)
                }
            )
            .draggable(list.id.uuidString) {
                SwiftUI.Label(list.name, systemImage: list.icon)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    // MARK: - Actions

    private func requestAreaDeletion(for requestedAreaIDs: Set<UUID>) {
        guard let pending = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: requestedAreaIDs,
            snapshot: collectionsSnapshot
        ) else {
            return
        }

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
        saveModelContextNow()
        selectedAreaIDs.subtract(rootSet)
    }

    private func deleteAreasMovingContentsToRoot(rootAreaIDs: [UUID]) {
        deleteAreasOnly(rootAreaIDs: rootAreaIDs)
    }

    private func deleteAreasAndContents(rootAreaIDs: [UUID]) {
        guard let deletionPlan = ListsSidebarAreaPlanner.buildDeletionPlan(
            requestedAreaIDs: Set(rootAreaIDs),
            snapshot: collectionsSnapshot
        ) else {
            return
        }
        let subtreeAreaIDs = deletionPlan.subtreeAreaIDs

        if let selectedList, let selectedListAreaID = selectedList.areaId, subtreeAreaIDs.contains(selectedListAreaID) {
            setRecentsSelection()
        }

        for list in lists where list.areaId.map(subtreeAreaIDs.contains) == true {
            modelContext.delete(list)
        }

        for areaID in ListsSidebarAreaPlanner.sortAreasDeepestFirst(subtreeAreaIDs, snapshot: collectionsSnapshot) {
            if let area = areaIndexByID[areaID] {
                modelContext.delete(area)
            }
        }

        saveModelContextNow()
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
        requestModelContextSave()
    }

    private func moveLabel(from source: IndexSet, to destination: Int) {
        var updatedLabels = sortedLabels
        updatedLabels.move(fromOffsets: source, toOffset: destination)

        // Update sort order
        for (index, label) in updatedLabels.enumerated() {
            label.sortOrder = index
        }
        requestModelContextSave()
    }

    private func moveTag(from source: IndexSet, to destination: Int) {
        var updatedTags = sortedTags
        updatedTags.move(fromOffsets: source, toOffset: destination)

        for (index, tag) in updatedTags.enumerated() {
            tag.sortOrder = index
        }
        requestModelContextSave()
    }

    private func renameList(_ listID: UUID) {
        guard let list = lists.first(where: { $0.id == listID }) else { return }
        editingList = list
        editingName = list.name
        showRenameAlert = true
    }

    private func changeListIcon(_ listID: UUID) {
        guard let list = lists.first(where: { $0.id == listID }) else { return }
        iconPickerList = list
    }

    private func deleteList(_ listID: UUID) {
        guard let list = lists.first(where: { $0.id == listID }) else { return }
        if selectedList?.id == list.id {
            setRecentsSelection()
        }
        modelContext.delete(list)
        saveModelContextNow()
    }

    private func renameArea(_ areaID: UUID) {
        guard let area = areas.first(where: { $0.id == areaID }) else { return }
        editingArea = area
        editingAreaName = area.name
        showAreaRenameAlert = true
    }

    private func renameLabel(_ labelID: UUID) {
        guard let label = labels.first(where: { $0.id == labelID }) else { return }
        onEditLabel(label)
    }

    private func changeLabelColor(_ labelID: UUID, color: LabelColor) {
        guard let label = labels.first(where: { $0.id == labelID }) else { return }
        label.color = color
        requestModelContextSave()
    }

    private func deleteLabel(_ labelID: UUID) {
        guard let label = labels.first(where: { $0.id == labelID }) else { return }
        let descriptor = FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.labelId == labelID }
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
        saveModelContextNow()
    }

    private func renameTag(_ tagID: UUID) {
        guard let tag = tags.first(where: { $0.id == tagID }) else { return }
        editingTag = tag
    }

    private func deleteTag(_ tagID: UUID) {
        guard let tag = tags.first(where: { $0.id == tagID }) else { return }
        if selectedTag?.id == tag.id {
            setRecentsSelection()
        }
        modelContext.delete(tag)
        saveModelContextNow()
    }

    private func setAreaExpanded(_ areaID: UUID, _ isExpanded: Bool) {
        guard let area = areas.first(where: { $0.id == areaID }) else { return }
        guard area.isExpanded != isExpanded else { return }
        area.isExpanded = isExpanded
        requestModelContextSave()
    }

    private func moveItemToRoot(_ draggedID: UUID) -> Bool {
        let descriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == draggedID })
        if let list = try? modelContext.fetch(descriptor).first {
            list.areaId = nil
            requestModelContextSave()
            return true
        }

        let areaDescriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == draggedID })
        guard let area = try? modelContext.fetch(areaDescriptor).first else { return false }
        area.parentId = nil
        requestModelContextSave()
        return true
    }

    private func moveListToRoot(_ draggedID: UUID) -> Bool {
        moveItemToRoot(draggedID)
    }

    private func moveList(_ list: ReadingList, toArea targetAreaID: UUID?) {
        guard list.areaId != targetAreaID else { return }
        list.areaId = targetAreaID
        list.updatedAt = Date()
        saveModelContextNow()
    }

    private func moveDroppedArticle(_ payload: SavedArticleDragPayload, to targetList: ReadingList) -> Bool {
        ArticleLibraryActions.moveDroppedArticle(
            payload,
            to: targetList,
            modelContext: modelContext
        )
    }

    private func applyDroppedArticle(_ payload: SavedArticleDragPayload, label: Label) -> Bool {
        ArticleLibraryActions.applyDroppedArticle(
            payload,
            labelId: label.id,
            defaultList: defaultDroppedArticleList,
            modelContext: modelContext
        )
    }

    private func addDroppedArticle(_ payload: SavedArticleDragPayload, tag: Tag) -> Bool {
        ArticleLibraryActions.addDroppedArticle(
            payload,
            tag: tag,
            modelContext: modelContext
        )
    }

    private var defaultDroppedArticleList: ReadingList? {
        lists.first { $0.name == "Inbox" } ?? lists.first
    }

    private func moveSavedArticleToList(_ articleID: UUID, _ listID: UUID) -> Bool {
        let articleDescriptor = FetchDescriptor<SavedArticle>(predicate: #Predicate { $0.id == articleID })
        let listDescriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == listID })

        guard let savedArticle = try? modelContext.fetch(articleDescriptor).first,
              let list = try? modelContext.fetch(listDescriptor).first else {
            return false
        }

        guard savedArticle.readingList?.id != list.id else { return false }

        let newArticle = SavedArticle(
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            extract: savedArticle.extract,
            thumbnailURL: savedArticle.thumbnailURL,
            list: list
        )
        newArticle.isRead = savedArticle.isRead
        newArticle.labelId = savedArticle.labelId
        newArticle.wordCount = savedArticle.wordCount
        list.articles.append(newArticle)
        list.updatedAt = Date()

        if let sourceList = savedArticle.readingList {
            sourceList.articles.removeAll { $0.id == savedArticle.id }
            sourceList.updatedAt = Date()
        }
        modelContext.delete(savedArticle)
        saveModelContextNow()
        return true
    }

    private func moveItemToArea(_ draggedID: UUID, _ targetAreaID: UUID) -> Bool {
        let listDescriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == draggedID })
        if let list = try? modelContext.fetch(listDescriptor).first {
            list.areaId = targetAreaID
            requestModelContextSave()
            return true
        }

        let areaDescriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == draggedID })
        guard let draggedArea = try? modelContext.fetch(areaDescriptor).first else { return false }
        guard draggedArea.id != targetAreaID else { return false }
        guard !ListsSidebarAreaPlanner.isDescendant(
            areaID: targetAreaID,
            of: draggedArea.id,
            parentAreaByID: collectionsSnapshot.parentAreaByID
        ) else {
            return false
        }

        draggedArea.parentId = targetAreaID
        requestModelContextSave()
        return true
    }
}

private struct SidebarHeaderAccessoryIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.secondary)
            .frame(
                width: SidebarRowMetrics.headerAccessorySize,
                height: SidebarRowMetrics.headerAccessorySize,
                alignment: .center
            )
            .contentShape(Rectangle())
    }
}

private struct ListsSidebarSectionHeader<Accessory: View>: View {
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics

    let title: String
    let accessory: Accessory

    init(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(SidebarRowMetrics.sectionHeaderFont)
                .foregroundStyle(.secondary)
                .textCase(nil)

            Spacer(minLength: 0)

            accessory
        }
        .font(SidebarRowMetrics.sectionHeaderFont)
        .frame(minHeight: SidebarRowMetrics.headerMinHeight, alignment: .bottom)
        .padding(.horizontal, layoutMetrics.horizontalInset)
        .textCase(nil)
    }
}

private struct SidebarRootRowLabel: View {
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let title: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: layoutMetrics.rowSpacing) {
            SidebarLeadingSlot {
                if let systemImage {
                    SidebarSymbolIcon(systemName: systemImage)
                } else {
                    Color.clear
                }
            }

            Text(title)
                .lineLimit(1)
                .foregroundStyle(SidebarRowSelectionVisuals.primaryForeground(isSelected: isSelected))

            Spacer(minLength: 0)
        }
    }
}

private struct ListRowView: View {
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let list: ReadingList
    let onRename: () -> Void
    let onChangeIcon: () -> Void
    let availableAreas: [Area]
    let onMoveToFolder: (UUID?) -> Void
    let onDelete: () -> Void
    let onArticleDrop: (SavedArticleDragPayload) -> Bool

    @State private var isArticleDropTargeted = false

    var body: some View {
        HStack(spacing: layoutMetrics.rowSpacing) {
            SidebarSymbolIcon(systemName: list.icon)
                .foregroundStyle(
                    SidebarRowSelectionVisuals.primaryForeground(
                        isSelected: isSelected,
                        isHighlighted: isArticleDropTargeted
                    )
                )

            Text(list.name)
                .lineLimit(1)
                .foregroundStyle(
                    SidebarRowSelectionVisuals.primaryForeground(
                        isSelected: isSelected,
                        isHighlighted: isArticleDropTargeted
                    )
                )

            Spacer(minLength: 0)

            if list.articles.count > 0 {
                SidebarCountBadge(count: list.articles.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarDropTargetStyle(isTargeted: isArticleDropTargeted)
        .accessibilityHint("Drag this list into a folder, or drop an article to move it into this list")
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

            Menu {
                Button {
                    onMoveToFolder(nil)
                } label: {
                    SwiftUI.Label(
                        "None",
                        systemImage: list.areaId == nil ? "checkmark.circle.fill" : "circle"
                    )
                }

                if !availableAreas.isEmpty {
                    Divider()
                }

                ForEach(availableAreas) { area in
                    Button {
                        onMoveToFolder(area.id)
                    } label: {
                        SwiftUI.Label(
                            area.name,
                            systemImage: list.areaId == area.id ? "checkmark.circle.fill" : area.icon
                        )
                    }
                }
            } label: {
                SwiftUI.Label("Move to Folder", systemImage: "folder")
            }

            Divider()

            Button("Delete", role: .destructive, action: onDelete)
        }
        .dropDestination(for: SavedArticleDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            return onArticleDrop(payload)
        } isTargeted: { targeted in
            isArticleDropTargeted = targeted
        }
    }
}

/// Label row for sidebar - displays colored circle and name
private struct LabelRowView: View {
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let label: Label
    let articleCount: Int
    let onPersistChange: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onArticleDrop: (SavedArticleDragPayload) -> Bool

    @State private var isArticleDropTargeted = false

    var body: some View {
        HStack(spacing: layoutMetrics.rowSpacing) {
            SidebarLeadingSlot {
                Circle()
                    .fill(label.color.swiftUIColor)
                    .frame(width: SidebarRowMetrics.labelDotSize, height: SidebarRowMetrics.labelDotSize)
            }

            Text(label.name)
                .lineLimit(1)
                .foregroundStyle(
                    SidebarRowSelectionVisuals.primaryForeground(
                        isSelected: isSelected,
                        isHighlighted: isArticleDropTargeted
                    )
                )

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarDropTargetStyle(isTargeted: isArticleDropTargeted)
        .accessibilityHint("Drop an article to assign this label")
        .contextMenu {
            labelContextMenu
        }
        .dropDestination(for: SavedArticleDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            return onArticleDrop(payload)
        } isTargeted: { targeted in
            isArticleDropTargeted = targeted
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
                onPersistChange()
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
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics
    @Environment(\.sidebarRowIsSelected) private var isSelected

    let tag: Tag
    let articleCount: Int
    let onRename: () -> Void
    let onDelete: () -> Void
    let onArticleDrop: (SavedArticleDragPayload) -> Bool

    @State private var isArticleDropTargeted = false

    var body: some View {
        HStack(spacing: layoutMetrics.rowSpacing) {
            SidebarSymbolIcon(systemName: "tag")
                .foregroundStyle(
                    SidebarRowSelectionVisuals.primaryForeground(
                        isSelected: isSelected,
                        isHighlighted: isArticleDropTargeted
                    )
                )

            Text(tag.name)
                .lineLimit(1)
                .foregroundStyle(
                    SidebarRowSelectionVisuals.primaryForeground(
                        isSelected: isSelected,
                        isHighlighted: isArticleDropTargeted
                    )
                )

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sidebarDropTargetStyle(isTargeted: isArticleDropTargeted)
        .accessibilityHint("Drop an article to add this tag")
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
        .dropDestination(for: SavedArticleDragPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            return onArticleDrop(payload)
        } isTargeted: { targeted in
            isArticleDropTargeted = targeted
        }
    }
}

/// Collapsible area/folder row with drop-to-add support and nested areas
private struct AreaRowView<ListRow: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @Environment(\.sidebarRowLayoutMetrics) private var layoutMetrics

    let area: Area
    let lists: [ReadingList]
    let childAreas: [Area]
    let parentAreaByID: [UUID: UUID?]
    @Binding var selectedAreaIDs: Set<UUID>
    let listRow: (ReadingList) -> ListRow
    let listsInArea: (Area) -> [ReadingList]
    let childAreasOf: (Area) -> [Area]
    let onRename: (Area) -> Void
    let onRequestDelete: (Set<UUID>) -> Void
    let onExpansionChange: (Area, Bool) -> Void
    let onPersistChange: () -> Void
    let isSelected: Bool

    @State private var isCollectionDropTargeted = false
    @State private var isArticleDropTargeted = false
    @State private var articleExpansionTask: Task<Void, Never>?

    private var deleteTargetAreaIDs: Set<UUID> {
        if selectedAreaIDs.contains(area.id) && selectedAreaIDs.count > 1 {
            return selectedAreaIDs
        }
        return [area.id]
    }

    private var deleteActionLabel: String {
        deleteTargetAreaIDs.count > 1 ? "Delete Selected Folders" : "Delete Folder"
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

    private var isDropTargeted: Bool {
        isCollectionDropTargeted || isArticleDropTargeted
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(
            get: { area.isExpanded },
            set: { newValue in
                if reduceMotion {
                    onExpansionChange(area, newValue)
                } else {
                    withAnimation(.easeOut(duration: 0.18)) {
                        onExpansionChange(area, newValue)
                    }
                }
            }
        )) {
            // Nested child areas first
            ForEach(childAreas) { childArea in
                AreaRowView(
                    area: childArea,
                    lists: listsInArea(childArea),
                    childAreas: childAreasOf(childArea),
                    parentAreaByID: parentAreaByID,
                    selectedAreaIDs: $selectedAreaIDs,
                    listRow: listRow,
                    listsInArea: listsInArea,
                    childAreasOf: childAreasOf,
                    onRename: onRename,
                    onRequestDelete: onRequestDelete,
                    onExpansionChange: onExpansionChange,
                    onPersistChange: onPersistChange,
                    isSelected: selectedAreaIDs.contains(childArea.id)
                )
            }

            // Lists in this area
            ForEach(lists) { list in
                listRow(list)
            }
        } label: {
            SidebarRowContainer(isSelected: isSelected) {
                HStack(spacing: layoutMetrics.rowSpacing) {
                    SidebarSymbolIcon(systemName: area.icon)
                        .foregroundStyle(
                            SidebarRowSelectionVisuals.primaryForeground(
                                isSelected: isSelected,
                                isHighlighted: isDropTargeted
                            )
                        )

                    Text(area.name)
                        .lineLimit(1)
                        .foregroundStyle(
                            SidebarRowSelectionVisuals.primaryForeground(
                                isSelected: isSelected,
                                isHighlighted: isDropTargeted
                            )
                        )

                    Spacer(minLength: 0)

                    if totalListCount > 0 {
                        SidebarCountBadge(count: totalListCount)
                    }
                }
            }
            .sidebarDropTargetStyle(isTargeted: isDropTargeted)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isDropTargeted)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(area.name)
            .accessibilityValue(totalListCount > 0 ? "\(totalListCount) lists" : "Empty folder")
            .accessibilityHint("Open or collapse this folder. Drag lists or folders here to move them inside.")
            .accessibilityIdentifier(SidebarSelectionID.area(area.id).accessibilityIdentifier)
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
        }
        .tag(SidebarSelectionID.area(area.id))
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .help("Drop lists or folders here to move them into \(area.name)")
        .draggable(area.id.uuidString) {
            SwiftUI.Label(area.name, systemImage: area.icon)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .dropDestination(for: String.self) { items, _ in
            guard ListsSidebarAreaArticleDropPolicy.behavior(
                for: .collectionDrop,
                isExpanded: area.isExpanded
            ) == .accept else {
                return false
            }
            guard let idString = items.first,
                  let uuid = UUID(uuidString: idString) else { return false }

            // Try to find as ReadingList first
            let listDescriptor = FetchDescriptor<ReadingList>(predicate: #Predicate { $0.id == uuid })
            if let list = try? modelContext.fetch(listDescriptor).first {
                list.areaId = area.id
                onPersistChange()
                return true
            }

            // Try to find as Area (for nesting areas)
            let areaDescriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == uuid })
            if let draggedArea = try? modelContext.fetch(areaDescriptor).first {
                // Prevent dropping area into itself or its descendants
                guard draggedArea.id != area.id else { return false }
                guard !ListsSidebarAreaPlanner.isDescendant(
                    areaID: area.id,
                    of: draggedArea.id,
                    parentAreaByID: parentAreaByID
                ) else {
                    return false
                }

                draggedArea.parentId = area.id
                onPersistChange()
                return true
            }

            return false
        } isTargeted: { targeted in
            isCollectionDropTargeted = targeted
        }
        .dropDestination(for: SavedArticleDragPayload.self) { items, _ in
            guard !items.isEmpty else { return false }
            return ListsSidebarAreaArticleDropPolicy.behavior(
                for: .directArticleDrop,
                isExpanded: area.isExpanded
            ) == .accept
        } isTargeted: { targeted in
            handleArticleHoverChange(targeted)
        }
        .onDisappear {
            articleExpansionTask?.cancel()
        }
    }

    private func handleArticleHoverChange(_ targeted: Bool) {
        isArticleDropTargeted = targeted
        articleExpansionTask?.cancel()
        articleExpansionTask = nil

        guard targeted else { return }
        guard case .expandAfterDelay(let delay) = ListsSidebarAreaArticleDropPolicy.behavior(
            for: .articleHover,
            isExpanded: area.isExpanded
        ) else {
            return
        }

        articleExpansionTask = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            guard isArticleDropTargeted, !area.isExpanded else { return }

            if reduceMotion {
                onExpansionChange(area, true)
            } else {
                withAnimation(.easeOut(duration: 0.18)) {
                    onExpansionChange(area, true)
                }
            }
        }
    }
}
