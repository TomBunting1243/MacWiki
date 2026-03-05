import SwiftUI

struct ReferenceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let sections: [ArticleReferenceSection]

    @State private var selectedReferenceIds: Set<String> = []

    private var totalCount: Int {
        sections.reduce(0) { $0 + $1.items.count }
    }

    private var selectionCount: Int {
        selectedReferenceIds.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            if !section.items.isEmpty {
                                ReferenceSectionHeaderView(title: section.title)

                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                    ReferenceRowView(
                                        item: item,
                                        displayLabel: ReferenceListHelpers.displayLabel(for: item, index: index),
                                        isSelected: selectedReferenceIds.contains(item.id),
                                        isFocused: appState.selectedReferenceId == item.id,
                                        hasLink: !item.links.isEmpty,
                                        onToggleSelection: {
                                            toggleSelection(for: item.id)
                                        },
                                        onOpen: {
                                            ReferenceListHelpers.openFirstLink(
                                                appState: appState,
                                                item: item
                                            ) { url in
                                                openURL(url)
                                            }
                                        },
                                        onCopy: { format in
                                            ReferenceListHelpers.copyReferences(
                                                format: format,
                                                sections: [ArticleReferenceSection(id: section.id, title: section.title, items: [item])],
                                                includeSectionHeaders: false
                                            )
                                        },
                                        onFocus: {
                                            appState.selectedReferenceId = item.id
                                        }
                                    )
                                }
                            }
                        }
                    }
                    .padding(.bottom, 86)
                }
                .scrollIndicators(.hidden)
                .onChange(of: appState.selectedReferenceId) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            if !sections.isEmpty {
                ReferenceExportBarView(
                    totalCount: totalCount,
                    selectionCount: selectionCount,
                    selectedSections: ReferenceListHelpers.filteredSections(
                        sections: sections,
                        selection: selectedReferenceIds
                    ),
                    allSections: sections,
                    onClearSelection: {
                        selectedReferenceIds.removeAll()
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: sections.isEmpty)
        .onChange(of: sections) { _, newValue in
            reconcileSelection(with: newValue)
        }
        .onChange(of: appState.currentArticle?.title) { _, _ in
            selectedReferenceIds.removeAll()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("References")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(totalCount)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())

                if selectionCount > 0 {
                    Text("Selected \(selectionCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.gray.opacity(0.12), in: Capsule())
                }

                Spacer()
            }
        }
    }
}

private extension ReferenceListView {
    func toggleSelection(for id: String) {
        if selectedReferenceIds.contains(id) {
            selectedReferenceIds.remove(id)
        } else {
            selectedReferenceIds.insert(id)
        }
    }

    func reconcileSelection(with newSections: [ArticleReferenceSection]) {
        let validIds = Set(newSections.flatMap { $0.items.map(\.id) })
        selectedReferenceIds = selectedReferenceIds.intersection(validIds)
    }

}
