import SwiftUI

struct SidebarSearchHeaderView: View {
    let model: SidebarSearchSurfaceModel
    let allLists: [ReadingList]
    @FocusState.Binding var isSearchFieldFocused: Bool
    let onSubmit: () -> Void
    let onClose: () -> Void
    let onMarkVisibleRead: () -> Void
    let onMarkVisibleUnread: () -> Void
    let onSaveVisibleToList: (ReadingList) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Search")
                        .font(MacWikiTypography.columnHeaderTitle)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.headerMetadataText)
                        .font(MacWikiTypography.columnHeaderMetadata)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    ControlGroup {
                        unreadFilterButton
                        sortMenu
                        actionsMenu
                    }
                    .controlSize(.small)

                    Button("Close Search", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: ChromeIconMetrics.compactButtonSize, height: ChromeIconMetrics.compactButtonSize)
                        .background(
                            RoundedRectangle(cornerRadius: TopChromeControlMetrics.accessoryCornerRadius(compact: true))
                                .fill(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.08))
                        )
                        .buttonStyle(.plain)
                        .help("Close Search")
                }
            }
            .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
            .padding(.top, 16)
            .padding(.bottom, 11)

            searchField
            .padding(.horizontal, ColumnChromeMetrics.horizontalPadding)
            .padding(.bottom, 12)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(ColumnChromeMetrics.dividerOpacity(for: colorScheme)))
                .frame(height: 0.5)
        }
    }

    private var searchField: some View {
        @Bindable var searchCoordinator = model.searchCoordinator

        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("Search Wikipedia...", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(MacWikiTypography.columnSearchField)
                .focused($isSearchFieldFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Search Wikipedia")
                .accessibilityIdentifier("sidebar-search-field")

            if model.searchCoordinator.isLoading {
                AppLoadingActivityMark(tone: .accent)
                    .frame(width: 14, height: 14)
            } else if model.searchCoordinator.hasInput {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    model.searchCoordinator.clearSearch()
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.05))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.16 : 0.09), lineWidth: 0.6)
        }
    }

    private var unreadFilterButton: some View {
        Button {
            model.readFilter = model.readFilter == .unread ? .all : .unread
        } label: {
            Image(systemName: model.readFilter == .unread ? "circle.inset.filled" : "circle")
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(model.readFilter == .unread ? Color.accentColor : .secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help(model.readFilter == .unread ? "Show all results" : "Show unread only")
    }

    private var sortMenu: some View {
        Menu {
            ForEach(SidebarSearchSortMode.allCases, id: \.self) { mode in
                Button {
                    model.sortMode = mode
                } label: {
                    HStack {
                        Text(mode.rawValue)
                        if model.sortMode == mode {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            SwiftUI.Label("Sort Results", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help("Sort")
    }

    private var actionsMenu: some View {
        Menu {
            if model.hasActiveViewOptions {
                Button("Reset View") {
                    model.resetFilters()
                }

                Divider()
            }

            Button {
                onMarkVisibleRead()
            } label: {
                SwiftUI.Label("Mark Visible as Read", systemImage: "checkmark.circle")
            }
            .disabled(model.visibleSnapshot.visibleUnreadCount == 0)

            Button {
                onMarkVisibleUnread()
            } label: {
                SwiftUI.Label("Mark Visible as Unread", systemImage: "circle")
            }
            .disabled(model.visibleSnapshot.visibleReadCount == 0)

            if !allLists.isEmpty {
                Divider()
                Menu("Save Visible to List") {
                    ForEach(allLists) { list in
                        Button(list.name) {
                            onSaveVisibleToList(list)
                        }
                    }
                }
                .disabled(model.visibleSnapshot.rows.isEmpty)
            }
        } label: {
            SwiftUI.Label("Search Actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
                .font(.system(size: ChromeIconMetrics.symbolPointSize, weight: ChromeIconMetrics.regularWeight))
                .imageScale(.medium)
                .foregroundStyle(.secondary)
                .frame(width: TopChromeControlMetrics.groupButtonSize, height: TopChromeControlMetrics.groupButtonSize)
        }
        .help("Actions")
    }
}
