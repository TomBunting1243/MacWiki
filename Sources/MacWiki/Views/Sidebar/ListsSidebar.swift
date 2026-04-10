import SwiftUI
import SwiftData

private enum SidebarChrome {
    static let headerAccessorySize: CGFloat = 18
    static let hoverCornerRadius: CGFloat = 7
}

enum SidebarSelectionID: Hashable {
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

private struct SidebarHoverRowModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState

    let isSelected: Bool

    @State private var isHovered = false

    private var hoverFill: Color {
        guard isHovered && !isSelected else { return .clear }
        let isKeyWindow = controlActiveState == .key
        if colorScheme == .dark {
            return Color.white.opacity(isKeyWindow ? 0.060 : 0.040)
        }
        return Color.black.opacity(isKeyWindow ? 0.032 : 0.022)
    }

    private var hoverStroke: Color {
        guard isHovered && !isSelected else { return .clear }
        let isKeyWindow = controlActiveState == .key
        if colorScheme == .dark {
            return Color.white.opacity(isKeyWindow ? 0.10 : 0.07)
        }
        return Color.black.opacity(isKeyWindow ? 0.055 : 0.04)
    }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: SidebarChrome.hoverCornerRadius, style: .continuous)
                    .fill(hoverFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: SidebarChrome.hoverCornerRadius, style: .continuous)
                            .strokeBorder(hoverStroke, lineWidth: 0.75)
                    }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                guard hovering != isHovered else { return }
                isHovered = hovering
            }
    }
}

/// Lists sidebar with reading lists management
struct ListsSidebar: View {
    @Environment(AppState.self) private var appState
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
    @State private var sidebarSelectionSet: Set<SidebarSelectionID> = []
    @State private var topObscuredHeight: CGFloat = 38
    @State private var selectedAreaIDs: Set<UUID> = []
    @AppStorage(AppStorageKey.ListsSidebar.sortOrder) private var sortOrder: ListSortOrder = .updatedDate

    // Editing state for lists
    @State private var editingList: ReadingList?
    @State private var editingName: String = ""
    @State private var showRenameAlert = false
    @State private var iconPickerList: ReadingList?
    @State private var showIconPickerSheet = false
    @AppStorage(AppStorageKey.Discover.openMode) private var discoverOpenMode: DiscoverOpenMode = .sidebar
    @AppStorage(ExperimentFlag.wikiHopPOCEnabled.key) private var isWikiHopEnabled = false
    @AppStorage(AppStorageKey.Features.wikiHopPostV1Enabled) private var isWikiHopPostV1Enabled = false

    // Editing state for areas
    @State private var editingArea: Area?
    @State private var editingAreaName: String = ""
    @State private var showAreaRenameAlert = false
    @State private var pendingAreaDeletion: PendingAreaDeletion?
    @State private var showAreaDeleteContentsPrompt = false
    @State private var collectionsSnapshot = ListsSidebarSnapshot.empty
    @State private var saveScheduler = DebouncedActionScheduler()

    // Tag management
    @State private var showNewTagSheet = false
    @State private var editingTag: Tag?

    @Query(sort: \Label.sortOrder) private var labels: [Label]
    @Query(sort: \Tag.sortOrder) private var tags: [Tag]

    let onEditLabel: (Label) -> Void
    let onAddNewLabel: () -> Void

    private var trimmedEditingName: String {
        editingName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
            isSearchDisabled: appState.isWikiHopNavigationLocked,
            isWikiHopAvailable: isWikiHopAvailable
        )
    }

    private var collectionsFingerprint: Int {
        listsSidebarSnapshotFingerprint(
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

    private func refreshCollectionsSnapshot() {
        collectionsSnapshot = ListsSidebarSnapshot(
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

    private func saveModelContextNow() {
        guard modelContext.hasChanges else { return }
        try? modelContext.save()
    }

    private func requestModelContextSave() {
        saveScheduler.schedule { [modelContext] in
            guard modelContext.hasChanges else { return }
            try? modelContext.save()
        }
    }

    private func flushScheduledModelContextSave() {
        saveScheduler.flush { [modelContext] in
            guard modelContext.hasChanges else { return }
            try? modelContext.save()
        }
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
                        requestModelContextSave()
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

    private var sidebarWithCollectionSnapshotSync: some View {
        sidebarWithDeleteDialog
            .onAppear {
                refreshCollectionsSnapshot()
                syncSelectionFromBindings()
                enforceWikiHopSelectionGuard()
            }
            .onChange(of: collectionsFingerprint) { _, _ in
                refreshCollectionsSnapshot()
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
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewReadingList)) { _ in
            showNewListSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .macWikiRequestNewFolder)) { _ in
            showNewAreaSheet = true
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var sidebarList: some View {
        List(selection: $sidebarSelectionSet) {
            ForEach(sidebarSections) { section in
                sidebarSectionView(section)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, max(0, topObscuredHeight), for: .scrollIndicators)
        .transaction { transaction in
            transaction.animation = nil
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isWikiHopAvailable)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateTopObscuredHeight(proxy.safeAreaInsets.top)
                    }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newValue in
                        updateTopObscuredHeight(newValue)
                    }
            }
        }
    }

    @ViewBuilder
    private func sidebarSectionView(_ section: ListsSidebarTreeSection) -> some View {
        switch section.kind {
        case .explore:
            Section {
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
                if !section.nodes.isEmpty {
                    ForEach(section.nodes) { node in
                        sidebarNodeView(node)
                    }
                }
            } header: {
                sidebarSectionHeader("Labels")
            }
        case .tags:
            Section {
                if !section.nodes.isEmpty {
                    ForEach(section.nodes) { node in
                        sidebarNodeView(node)
                    }
                }
            } header: {
                sidebarSectionHeader("Tags")
            }
        }
    }

    private func sidebarSectionHeader<Accessory: View>(
        _ title: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .textCase(nil)
            Spacer(minLength: 0)
            accessory()
        }
        .textCase(nil)
    }

    private func sidebarSectionHeader(_ title: String) -> some View {
        sidebarSectionHeader(title) { EmptyView() }
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

            Button("New Label") {
                onAddNewLabel()
            }
            Button("New Tag") {
                showNewTagSheet = true
            }

            Divider()

            Picker("Sort", selection: $sortOrder) {
                ForEach(ListSortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(
                    width: SidebarChrome.headerAccessorySize,
                    height: SidebarChrome.headerAccessorySize,
                    alignment: .center
                )
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .help("Sidebar Actions")
        .accessibilityIdentifier("sidebar-actions-menu")
    }

    private func rootRowLabel(_ title: String, systemImage: String? = nil) -> some View {
        Group {
            if let systemImage {
                SwiftUI.Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private func sidebarNodeView(_ node: ListsSidebarTreeNode) -> some View {
        switch node.kind {
        case .search(let isDisabled):
            sidebarSelectableRow(
                selection: .search,
                isSelected: sidebarSelectionSet.contains(.search),
                isDisabled: isDisabled
            ) {
                rootRowLabel("Search", systemImage: "magnifyingglass")
            }
        case .root(let selection):
            sidebarSelectableRow(
                selection: .root(selection),
                isSelected: sidebarSelectionSet.contains(.root(selection))
            ) {
                rootRowLabel(rootTitle(for: selection), systemImage: rootSystemImage(for: selection))
            }
        case .list(let list):
            listRow(for: list)
        case .label(let label):
            sidebarSelectableRow(
                selection: .label(label.id),
                isSelected: sidebarSelectionSet.contains(.label(label.id))
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
                    }
                )
            }
        case .tag(let tag):
            sidebarSelectableRow(
                selection: .tag(tag.id),
                isSelected: sidebarSelectionSet.contains(.tag(tag.id))
            ) {
                TagRowView(
                    tag: tag,
                    articleCount: tagArticleCounts[tag.id] ?? 0,
                    onRename: {
                        editingTag = tag
                    },
                    onDelete: {
                        deleteTag(tag.id)
                    }
                )
            }
        case .area(let area):
            AreaRowView(
                area: area,
                lists: listsInArea(area),
                childAreas: childAreas(of: area),
                parentAreaByID: collectionsSnapshot.parentAreaByID,
                selectedList: $selectedList,
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
                onPersistChange: requestModelContextSave,
                onCollapseHidingSelectedList: {
                    setRecentsSelection()
                },
                isSelected: selectedAreaIDs.contains(area.id)
            )
        }
    }

    private func sidebarSelectableRow<Content: View>(
        selection: SidebarSelectionID,
        isSelected: Bool = false,
        isDisabled: Bool = false,
        @ViewBuilder label: () -> Content
    ) -> some View {
        label()
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SidebarHoverRowModifier(isSelected: isSelected))
            .tag(selection)
            .disabled(isDisabled)
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
        topObscuredHeight = resolved
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
                    showIconPickerSheet = true
                },
                onDelete: {
                    withAnimation {
                        if selectedList?.id == list.id {
                            setRecentsSelection()
                        }
                        modelContext.delete(list)
                        saveModelContextNow()
                    }
                }
            )
            .draggable(list.id.uuidString) {
                SwiftUI.Label(list.name, systemImage: list.icon)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let idString = items.first,
                      let uuid = UUID(uuidString: idString) else { return false }

                return moveItemToRoot(uuid)
            }
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
            return ListsSidebarSnapshot.compareAreasForSortOrder(lhs, rhs)
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
        saveModelContextNow()
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
        showIconPickerSheet = true
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
        guard !isDescendant(areaID: targetAreaID, of: draggedArea.id) else { return false }

        draggedArea.parentId = targetAreaID
        requestModelContextSave()
        return true
    }

    private func isDescendant(areaID potentialDescendantID: UUID, of potentialAncestorID: UUID) -> Bool {
        var currentID: UUID? = potentialDescendantID
        while let resolvedID = currentID {
            if resolvedID == potentialAncestorID {
                return true
            }
            currentID = collectionsSnapshot.parentAreaByID[resolvedID] ?? nil
        }
        return false
    }
}
private struct ListRowView: View {
    @Environment(\.modelContext) private var modelContext

    let list: ReadingList
    let onRename: () -> Void
    let onChangeIcon: () -> Void
    let onDelete: () -> Void

    @State private var isArticleDropTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            SwiftUI.Label(list.name, systemImage: list.icon)
                .lineLimit(1)
                .foregroundStyle(isArticleDropTargeted ? Color.accentColor : .primary)

            Spacer(minLength: 0)

            if list.articles.count > 0 {
                SidebarCountBadge(count: list.articles.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let label: Label
    let articleCount: Int
    let onPersistChange: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(label.color.swiftUIColor)
                .frame(width: 8, height: 8)

            Text(label.name)
                .lineLimit(1)

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let tag: Tag
    let articleCount: Int
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            SwiftUI.Label(tag.name, systemImage: "tag")
                .lineLimit(1)

            Spacer(minLength: 0)

            if articleCount > 0 {
                SidebarCountBadge(count: articleCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let count: Int

    var body: some View {
        Text(count.formatted())
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .frame(minWidth: 18, alignment: .trailing)
    }
}



/// Collapsible area/folder row with drop-to-add support and nested areas
private struct AreaRowView<ListRow: View>: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let area: Area
    let lists: [ReadingList]
    let childAreas: [Area]
    let parentAreaByID: [UUID: UUID?]
    @Binding var selectedList: ReadingList?
    @Binding var selectedAreaIDs: Set<UUID>
    let listRow: (ReadingList) -> ListRow
    let listsInArea: (Area) -> [ReadingList]
    let childAreasOf: (Area) -> [Area]
    let onRename: (Area) -> Void
    let onRequestDelete: (Set<UUID>) -> Void
    let onPersistChange: () -> Void
    let onCollapseHidingSelectedList: () -> Void
    let isSelected: Bool

    @State private var isTargeted = false

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
                onPersistChange()
            }
        )) {
            // Nested child areas first
            ForEach(childAreas) { childArea in
                AreaRowView(
                    area: childArea,
                    lists: listsInArea(childArea),
                    childAreas: childAreasOf(childArea),
                    parentAreaByID: parentAreaByID,
                    selectedList: $selectedList,
                    selectedAreaIDs: $selectedAreaIDs,
                    listRow: listRow,
                    listsInArea: listsInArea,
                    childAreasOf: childAreasOf,
                    onRename: onRename,
                    onRequestDelete: onRequestDelete,
                    onPersistChange: onPersistChange,
                    onCollapseHidingSelectedList: onCollapseHidingSelectedList,
                    isSelected: selectedAreaIDs.contains(childArea.id)
                )
            }

            // Lists in this area
            ForEach(lists) { list in
                listRow(list)
            }
        } label: {
            HStack(spacing: 8) {
                SwiftUI.Label(area.name, systemImage: area.icon)
                    .foregroundStyle(isTargeted ? Color.accentColor : .primary)

                Spacer()

                // Total list count badge (including nested)
                if totalListCount > 0 {
                    SidebarCountBadge(count: totalListCount)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SidebarHoverRowModifier(isSelected: isSelected))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isTargeted)
        }
        .tag(SidebarSelectionID.area(area.id))
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
                onPersistChange()
                return true
            }

            // Try to find as Area (for nesting areas)
            let areaDescriptor = FetchDescriptor<Area>(predicate: #Predicate { $0.id == uuid })
            if let draggedArea = try? modelContext.fetch(areaDescriptor).first {
                // Prevent dropping area into itself or its descendants
                guard draggedArea.id != area.id else { return false }
                guard !isDescendant(areaID: area.id, of: draggedArea.id) else { return false }

                draggedArea.parentId = area.id
                onPersistChange()
                return true
            }

            return false
        } isTargeted: { targeted in
            isTargeted = targeted
        }
    }

    private func isDescendant(areaID potentialDescendantID: UUID, of potentialAncestorID: UUID) -> Bool {
        var currentID: UUID? = potentialDescendantID
        while let resolvedID = currentID {
            if resolvedID == potentialAncestorID {
                return true
            }
            currentID = parentAreaByID[resolvedID] ?? nil
        }
        return false
    }
}
