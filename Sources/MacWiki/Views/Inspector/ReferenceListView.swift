import SwiftUI

struct ReferenceListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openURL) private var openURL

    let sections: [ArticleReferenceSection]

    @State private var selectedReferenceIds: Set<String> = []
    @State private var suppressNextReferenceScroll = false

    private var visibleSections: [ArticleReferenceSection] {
        ReferenceListHelpers.visibleSections(from: sections)
    }

    private var totalCount: Int {
        visibleSections.reduce(0) { $0 + $1.items.count }
    }

    private var selectionCount: Int {
        selectedReferenceIds.count
    }

    private enum Metrics {
        static let topChromeReservation: CGFloat = 58
        static let bottomChromeReservation: CGFloat = 92
        static let horizontalPadding: CGFloat = 16
        static let topPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 14
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(visibleSections) { section in
                            if !section.items.isEmpty {
                                ReferenceSectionHeaderView(title: section.title)

                                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                                    ReferenceRowView(
                                        item: item,
                                        displayLabel: ReferenceListHelpers.displayLabel(for: item, index: index),
                                        isSelected: selectedReferenceIds.contains(item.id),
                                        isFocused: appState.selectedReferenceId == item.id,
                                        hasOpenTarget: ReferenceListHelpers.canOpen(item),
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
                                            suppressNextReferenceScroll = appState.selectedReferenceId != item.id
                                            appState.selectedReferenceId = item.id
                                        }
                                    )
                                    .id(item.id)
                                }
                            }
                        }
                    }
                    .padding(.top, Metrics.topChromeReservation)
                    .padding(.horizontal, Metrics.horizontalPadding)
                    .padding(.bottom, visibleSections.isEmpty ? 12 : Metrics.bottomChromeReservation)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.visible)
                .onChange(of: appState.selectedReferenceId) { _, newValue in
                    guard let newValue else { return }
                    if suppressNextReferenceScroll {
                        suppressNextReferenceScroll = false
                        return
                    }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }

            header
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.top, Metrics.topPadding)
                .zIndex(1)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if !visibleSections.isEmpty {
                ReferenceExportBarView(
                    totalCount: totalCount,
                    selectionCount: selectionCount,
                    selectedSections: ReferenceListHelpers.filteredSections(
                        sections: visibleSections,
                        selection: selectedReferenceIds
                    ),
                    allSections: visibleSections,
                    onClearSelection: {
                        selectedReferenceIds.removeAll()
                    }
                )
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.bottom, Metrics.bottomPadding)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: visibleSections.isEmpty)
        .onChange(of: sections) { _, newValue in
            reconcileSelection(with: ReferenceListHelpers.visibleSections(from: newValue))
        }
        .onChange(of: appState.currentArticle?.title) { _, _ in
            selectedReferenceIds.removeAll()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("References")
                .font(MacWikiTypography.inspectorSectionLabel)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("\(totalCount)")
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())

            if selectionCount > 0 {
                Text("Selected \(selectionCount)")
                    .font(MacWikiTypography.compactRowMetadata)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.gray.opacity(0.12), in: Capsule())
            }

            Spacer(minLength: 6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.58)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
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
