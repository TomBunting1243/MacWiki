import SwiftUI

struct SidebarSearchResultsView: View {
    let model: SidebarSearchSurfaceModel
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let onOpenRow: (SidebarSearchRow, Bool) -> Void
    let onToggleRead: (SidebarSearchRow) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if model.labelFilter != nil || model.tagFilter != nil {
                    SidebarSearchActiveFiltersRow(
                        label: model.labelFilter,
                        tag: model.tagFilter,
                        onClearLabel: model.clearLabelFilter,
                        onClearTag: model.clearTagFilter
                    )
                }

                ForEach(model.visibleSnapshot.rows) { row in
                    SidebarSearchResultRowView(
                        row: row,
                        isSelected: model.selectedRowID == row.id,
                        selectedTagId: model.tagFilter?.id,
                        allLists: allLists,
                        allLabels: allLabels,
                        allTags: allTags,
                        onOpenRow: onOpenRow,
                        onToggleRead: onToggleRead,
                        onLabelClick: { label in
                            model.toggleLabelFilter(label)
                        },
                        onTagClick: { tag in
                            model.toggleTagFilter(tag)
                        },
                        onShowPageViews: {
                            model.presentPageViews(for: row)
                        }
                    )
                    .id(row.id)
                    .popover(
                        isPresented: Binding(
                            get: { model.activePageViewsPopover?.rowID == row.id },
                            set: { isPresented in
                                guard !isPresented else { return }
                                model.dismissPageViews(for: row.id)
                            }
                        ),
                        arrowEdge: .trailing
                    ) {
                        if let payload = model.activePageViewsPopover, payload.rowID == row.id {
                            SidebarPageViewsPopoverContent(
                                title: payload.title,
                                referenceDate: Date()
                            )
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: model.selectedRowID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }
}

private struct SidebarSearchActiveFiltersRow: View {
    let label: Label?
    let tag: Tag?
    let onClearLabel: () -> Void
    let onClearTag: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if let label {
                HStack(spacing: 6) {
                    Circle()
                        .fill(label.color.swiftUIColor)
                        .frame(width: 7, height: 7)

                    Text(label.name)

                    clearButton(action: onClearLabel)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(label.color.swiftUIColor.opacity(0.10), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(label.color.swiftUIColor.opacity(0.18), lineWidth: 0.8)
                }
            }

            if let tag {
                HStack(spacing: 6) {
                    TagChipView(title: tag.name, isSelected: true)

                    clearButton(action: onClearTag)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 10, bottom: 3, trailing: 10))
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .help("Clear Filter")
        .accessibilityLabel("Clear filter")
    }
}
