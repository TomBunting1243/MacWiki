import SwiftUI

struct SidebarSearchHeaderView: View {
    private enum Metrics {
        static let titleFont = Font.system(size: 17, weight: .semibold)
        static let metadataFont = Font.subheadline.weight(.semibold)
    }

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
                VStack(alignment: .leading, spacing: 2) {
                    Text("Search")
                        .font(Metrics.titleFont)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(model.headerMetadataText)
                        .font(Metrics.metadataFont)
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
            .padding(.top, 12)
            .padding(.bottom, 10)

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

        return HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 15, alignment: .center)

            TextField("Search Wikipedia", text: $searchCoordinator.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isSearchFieldFocused)
                .onSubmit(onSubmit)
                .accessibilityLabel("Search Wikipedia")
                .accessibilityIdentifier("sidebar-search-field")

            if searchCoordinator.isLoading {
                AppLoadingActivityMark(
                    tone: .accent,
                    accessibilityLabel: "Searching Wikipedia"
                )
                    .frame(width: 13, height: 13)
            } else if searchCoordinator.hasInput {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    searchCoordinator.clearSearch()
                    isSearchFieldFocused = true
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .buttonStyle(.plain)
                .help("Clear Search")
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.35 : 0.55), lineWidth: 0.5)
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
        .accessibilityLabel("Unread only")
        .accessibilityValue(model.readFilter == .unread ? "Enabled" : "Disabled")
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
