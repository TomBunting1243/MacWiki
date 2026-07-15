import SwiftUI

struct SidebarSearchHeaderView: View {
    private enum Metrics {
        static let titleFont = Font.system(size: 17, weight: .semibold)
        static let metadataFont = Font.subheadline.weight(.semibold)
    }

    let model: SidebarSearchSurfaceModel
    let allLists: [ReadingList]
    @Binding var isSearchFieldFocused: Bool
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

                ControlGroup {
                    unreadFilterButton
                    sortMenu
                    actionsMenu
                    Button("Close Search", systemImage: "xmark", action: onClose)
                        .labelStyle(.iconOnly)
                        .help("Close Search")
                }
                .controlSize(.small)
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

        return NativeSidebarSearchField(
            text: $searchCoordinator.searchText,
            isFocused: $isSearchFieldFocused,
            onMoveDown: model.moveSelectionDown,
            onMoveUp: model.moveSelectionUp,
            onSubmit: onSubmit,
            onCancel: onClose
        )
        .frame(height: 24)
    }

    private var unreadFilterButton: some View {
        Button {
            model.readFilter = model.readFilter == .unread ? .all : .unread
        } label: {
            Image(systemName: model.readFilter == .unread ? "circle.inset.filled" : "circle")
                .foregroundStyle(model.readFilter == .unread ? Color.accentColor : .secondary)
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
        }
        .help("Actions")
    }
}
