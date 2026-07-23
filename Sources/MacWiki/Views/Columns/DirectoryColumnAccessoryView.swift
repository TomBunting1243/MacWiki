import SwiftUI

/// A lightweight, query-free companion for the native List Contents split item.
/// The content host remains the single owner of SwiftData observation and work;
/// this accessory renders shared snapshots and sends semantic commands back.
struct DirectoryColumnAccessoryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.macWikiAccessibilityPersonalization.reduceMotion) private var reduceMotion
    @AppStorage(AppStorageKey.Recents.scope) private var recentsScope: RecentsScope = .currentTab
    @AppStorage(AppStorageKey.Discover.sidebarTimeMachineHidden) private var discoverTimeMachineHidden = false

    @Binding var selectedList: ReadingList?
    @Binding var rootSelection: SidebarRootSelection

    let selectedLabel: Label?
    let selectedTag: Tag?
    let sidebarSearchModel: SidebarSearchSurfaceModel
    @Bindable var columnState: DirectoryColumnState

    var body: some View {
        Group {
            if appState.showSearch {
                SidebarSearchHeaderView(
                    model: sidebarSearchModel,
                    allLists: columnState.availableLists,
                    isSearchFieldFocused: Binding(
                        get: { columnState.isSearchFieldFocused },
                        set: { columnState.isSearchFieldFocused = $0 }
                    ),
                    onSubmit: openSelectedSearchRow,
                    onClose: dismissSearch,
                    onMarkVisibleRead: {
                        columnState.send(.markSearchVisible(asRead: true))
                    },
                    onMarkVisibleUnread: {
                        columnState.send(.markSearchVisible(asRead: false))
                    },
                    onSaveVisibleToList: { list in
                        columnState.send(.saveSearchVisible(listID: list.id))
                    }
                )
            } else {
                pinnedHeader
            }
        }
    }

    private var pinnedHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            headerIdentity

            Spacer(minLength: 8)

            headerControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: ColumnChromeMetrics.directoryBarHeight, alignment: .center)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(MacWikiTypography.columnHeaderTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)

            metadataLine
        }
        .layoutPriority(1)
    }

    @ViewBuilder
    private var metadataLine: some View {
        if rootSelection == .discover {
            HStack(spacing: 6) {
                Text(discoverEditionStatus)
                    .font(MacWikiTypography.columnHeaderMetadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if discoverArticleCount > 0 {
                    Text("·")
                        .font(MacWikiTypography.columnHeaderMetadata)
                        .foregroundStyle(.tertiary)

                    Text("\(discoverArticleCount) articles")
                        .font(MacWikiTypography.columnHeaderMetadata)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }

                if discoverFeedStore.isLoading {
                    Text("·")
                        .font(MacWikiTypography.columnHeaderMetadata)
                        .foregroundStyle(.tertiary)

                    Text(discoverFeedStore.feed == nil ? "Loading" : "Updating")
                        .font(MacWikiTypography.columnHeaderMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    articleCountLabel

                    if !columnState.selectedSavedArticleIDs.isEmpty {
                        Text("·")
                            .font(MacWikiTypography.columnHeaderMetadata)
                            .foregroundStyle(.tertiary)

                        Text("\(columnState.selectedSavedArticleIDs.count) selected")
                            .font(MacWikiTypography.columnHeaderMetadata)
                            .foregroundStyle(.secondary)
                    }
                }

                articleCountLabel
            }
        }
    }

    private var articleCountLabel: some View {
        HStack(spacing: 3) {
            Text("\(visibleArticleCount)")
                .font(MacWikiTypography.columnHeaderMetadata)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Text(visibleArticleCount == 1 ? "article" : "articles")
                .font(MacWikiTypography.columnHeaderMetadata)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var headerControls: some View {
        if rootSelection == .discover {
            discoverControls
        } else {
            ControlGroup {
                viewOptionsMenu
                batchActionsMenu
            }
            .controlSize(.regular)
        }
    }

    private var discoverControls: some View {
        SidebarDiscoverHeaderControls(
            showsTimeMachine: !discoverTimeMachineHidden,
            isRefreshEnabled: !discoverFeedStore.isLoading,
            timeMachineAccessibilityValue: discoverFeedStore.isLoading
                ? "Updating \(longDiscoverDateLabel)"
                : longDiscoverDateLabel,
            onRefresh: refreshDiscover
        ) {
            SidebarDiscoverTimeMachineView(
                selectedDate: Binding(
                    get: { appState.selectedDiscoverDate },
                    set: { appState.selectedDiscoverDate = $0 }
                ),
                isHidden: $discoverTimeMachineHidden,
                visibleEditionDateLabel: discoverFeedStore.feed?.dateLabel,
                isLoading: discoverFeedStore.isLoading,
                isTimeTraveling: isTimeTraveling,
                onRefresh: refreshDiscover
            )
            .defaultAppStorage(MacWikiDefaults.current)
        }
    }

    private var viewOptionsMenu: some View {
        Menu("View", systemImage: "line.3.horizontal.decrease") {
            Picker("Show", selection: unreadFilterBinding) {
                Text("All Articles").tag(false)
                Text("Unread Only").tag(true)
            }

            Picker("Sort", selection: sortModeBinding) {
                ForEach(DirectorySupplementalSortMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
        }
        .help("Filter and sort articles")
        .accessibilityValue(
            "\(isUnreadFilterEnabled ? "Unread only" : "All articles"), sorted by \(activeSortMode.rawValue)"
        )
    }

    private var batchActionsMenu: some View {
        Menu {
            if hasSelection {
                Button("Clear Selection") {
                    columnState.send(.clearSelection)
                }

                if !columnState.availableLabels.isEmpty {
                    Menu("Set Label on Selected") {
                        Button("None") {
                            columnState.send(.setSelectionLabel(labelID: nil))
                        }
                        Divider()
                        ForEach(columnState.availableLabels) { label in
                            Button(label.name) {
                                columnState.send(.setSelectionLabel(labelID: label.id))
                            }
                        }
                    }
                }

                if !columnState.availableTags.isEmpty {
                    Menu("Add Tag to Selected") {
                        ForEach(columnState.availableTags) { tag in
                            Button(tag.name) {
                                columnState.send(.addSelectionTag(tagID: tag.id))
                            }
                        }
                    }

                    Menu("Remove Tag from Selected") {
                        ForEach(columnState.availableTags) { tag in
                            Button(tag.name) {
                                columnState.send(.removeSelectionTag(tagID: tag.id))
                            }
                        }
                    }
                }

                if !selectionEligibleLists.isEmpty {
                    Menu("Add Selected to List") {
                        ForEach(selectionEligibleLists) { list in
                            Button(list.name) {
                                columnState.send(.addSelectionToList(listID: list.id))
                            }
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    columnState.send(.requestDeleteSelection)
                } label: {
                    SwiftUI.Label("Delete Selected", systemImage: "trash")
                }

                Divider()
            }

            Button {
                columnState.send(.markVisible(asRead: true))
            } label: {
                SwiftUI.Label("Mark Visible as Read", systemImage: "checkmark.circle")
            }
            .disabled(currentVisibleSnapshot.visibleUnreadCount == 0)

            Button {
                columnState.send(.markVisible(asRead: false))
            } label: {
                SwiftUI.Label("Mark Visible as Unread", systemImage: "circle")
            }
            .disabled(currentVisibleSnapshot.visibleReadCount == 0)
        } label: {
            SwiftUI.Label("Actions", systemImage: "ellipsis.circle")
        }
        .help("Batch actions")
    }

    private var unreadFilterBinding: Binding<Bool> {
        Binding(
            get: { isUnreadFilterEnabled },
            set: { columnState.send(.setUnreadFilter(isEnabled: $0)) }
        )
    }

    private var sortModeBinding: Binding<DirectorySupplementalSortMode> {
        Binding(
            get: { activeSortMode },
            set: { columnState.send(.setSortMode($0)) }
        )
    }

    private var isUnreadFilterEnabled: Bool {
        if let selectedList {
            return selectedList.filterMode == .unread
        }
        return columnState.supplementalReadFilter == .unread
    }

    private var activeSortMode: DirectorySupplementalSortMode {
        guard let selectedList else {
            return columnState.supplementalSortMode
        }
        switch selectedList.sortMode {
        case .title:
            return .title
        case .articleLength:
            return .articleLength
        case .addedDate, .manual:
            return .recent
        }
    }

    private var title: String {
        if let selectedList {
            return selectedList.name
        }
        if let selectedLabel {
            return selectedLabel.name
        }
        if let selectedTag {
            return selectedTag.name
        }
        if rootSelection == .discover {
            return "Discover"
        }
        if rootSelection == .wikiHop {
            return "Wiki-Hop"
        }
        if recentsScope == .currentTab,
           let activeID = appState.activeTabId,
           appState.openTabs.contains(where: { $0.id == activeID }) {
            return "Tab History"
        }
        return "Recent"
    }

    private var visibleArticleCount: Int {
        currentVisibleSnapshot.visibleTitles.count
    }

    private var currentVisibleSnapshot: DirectoryVisibleSnapshot {
        guard columnState.visibleSnapshotScopeKey == snapshotScopeKey else {
            return .empty
        }
        return columnState.visibleSnapshot
    }

    private var snapshotScopeKey: String {
        if let listID = selectedList?.id {
            return "list:\(listID.uuidString)"
        }
        if let labelID = selectedLabel?.id {
            return "label:\(labelID.uuidString)"
        }
        if let tagID = selectedTag?.id {
            return "tag:\(tagID.uuidString)"
        }
        return "root:\(rootSelection.rawValue):\(recentsScope.rawValue)"
    }

    private var hasSelection: Bool {
        !columnState.selectedSavedArticleIDs.isEmpty
    }

    private var selectionEligibleLists: [ReadingList] {
        guard let selectedList else { return columnState.availableLists }
        return columnState.availableLists.filter { $0.id != selectedList.id }
    }

    private var discoverFeedStore: DiscoverFeedStore {
        appState.discoverFeedStore
    }

    private var discoverArticleCount: Int {
        guard let feed = discoverFeedStore.feed else { return 0 }
        return SidebarDiscoverArticleInventory.articles(in: feed).count
    }

    private var discoverReferenceDate: Date {
        Calendar.current.startOfDay(for: appState.selectedDiscoverDate)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(discoverReferenceDate)
    }

    private var discoverEditionStatus: String {
        isToday ? "Today" : longDiscoverDateLabel
    }

    private var longDiscoverDateLabel: String {
        AppPresentationFormatting.longDate(discoverReferenceDate)
    }

    private var isTimeTraveling: Bool {
        guard discoverFeedStore.isLoading,
              let visibleFeed = discoverFeedStore.feed else {
            return false
        }
        return visibleFeed.dateKey != Self.discoverFeedDateFormatter.string(from: discoverReferenceDate)
    }

    private func refreshDiscover() {
        columnState.send(.refreshDiscover)
    }

    private func openSelectedSearchRow() {
        guard let row = sidebarSearchModel.selectedRow
                ?? sidebarSearchModel.visibleSnapshot.rows.first else {
            return
        }
        sidebarSearchModel.select(rowID: row.id)
        if SystemBridge.isOptionPressed {
            appState.presentOptionClickSavePrompt(for: row.article)
            return
        }
        appState.openArticle(
            row.article,
            inNewTab: appState.searchContext == .newTab || SystemBridge.isCommandPressed
        )
    }

    private func dismissSearch() {
        withAnimation(reduceMotion ? nil : ColumnMotion.sidebarVisibility) {
            appState.showSearch = false
        }
    }

    private static let discoverFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()
}
