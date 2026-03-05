import SwiftUI
import SwiftData

struct HighlightListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.sortOrder) private var allTags: [Tag]

    let highlights: [Highlight]
    @State private var showStaleHighlights = true
    @State private var showArchivedHighlights = false
    @State private var showArchiveMissingConfirmation = false

    private var activeHighlights: [Highlight] {
        highlights.filter { !$0.isArchived }
    }

    private var archivedHighlights: [Highlight] {
        highlights.filter { $0.isArchived }
    }

    private var staleHighlights: [Highlight] {
        activeHighlights.filter { $0.isStale }
    }

    private var staleHighlightCount: Int {
        staleHighlights.count
    }

    private var archivedHighlightCount: Int {
        archivedHighlights.count
    }

    private var showsRehydrateBar: Bool {
        staleHighlightCount > 0 || appState.isHighlightArticleRefreshInProgress
    }

    private var visibleHighlights: [Highlight] {
        var filtered = highlights.filter { highlight in
            if highlight.isArchived {
                return showArchivedHighlights
            }
            if !showStaleHighlights && highlight.isStale {
                return false
            }
            return true
        }
        if let tagId = appState.highlightTagFilterId {
            filtered = filtered.filter { highlight in
                highlight.tags.contains { $0.id == tagId }
            }
        }
        return filtered
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if visibleHighlights.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleHighlights, id: \.id) { highlight in
                                HighlightRowView(
                                    highlight: highlight,
                                    allTags: allTags,
                                    onDelete: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            deleteHighlight(highlight)
                                        }
                                    },
                                    onTagSelected: { tag in
                                        if appState.highlightTagFilterId == tag.id {
                                            appState.highlightTagFilterId = nil
                                        } else {
                                            appState.highlightTagFilterId = tag.id
                                        }
                                    }
                                )
                                .id(highlight.id)
                            }
                        }
                        .padding(.bottom, 12)
                        .padding(.bottom, showsRehydrateBar ? 86 : 0)
                    }
                    .onChange(of: appState.selectedHighlightId) { _, newValue in
                        guard let newValue,
                              let targetId = UUID(uuidString: newValue) else {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            if showsRehydrateBar {
                HighlightRehydrateBarView(
                    staleCount: staleHighlightCount,
                    isRefreshing: appState.isHighlightArticleRefreshInProgress,
                    onRefreshArticle: requestArticleRefresh,
                    onArchiveMissing: {
                        showArchiveMissingConfirmation = true
                    }
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: showsRehydrateBar)
        .confirmationDialog(
            "Archive stale highlights?",
            isPresented: $showArchiveMissingConfirmation,
            titleVisibility: .visible
        ) {
            Button(
                staleHighlightCount == 1 ? "Archive 1 Highlight" : "Archive \(staleHighlightCount) Highlights"
            ) {
                archiveStaleHighlights()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Archived highlights are hidden from the article and Notes list, and can be restored later.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "highlighter")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("Highlights")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("\(visibleHighlights.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())

                Spacer()

                if !staleHighlights.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showStaleHighlights.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(staleHighlights.count)")
                                .font(.caption.weight(.medium))
                            Text("Stale")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(showStaleHighlights ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            showStaleHighlights
                                ? Color.orange.opacity(0.18)
                                : Color.gray.opacity(0.12),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule()
                                .strokeBorder(
                                    showStaleHighlights ? Color.orange.opacity(0.4) : Color.clear,
                                    lineWidth: 0.8
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .help(showStaleHighlights ? "Hide stale highlights" : "Show stale highlights")
                }

                if archivedHighlightCount > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showArchivedHighlights.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "archivebox")
                                .font(.system(size: 9, weight: .semibold))
                            Text("\(archivedHighlightCount)")
                                .font(.caption.weight(.medium))
                            Text("Archived")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(showArchivedHighlights ? .secondary : .tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            showArchivedHighlights
                                ? Color.gray.opacity(0.12)
                                : Color.gray.opacity(0.08),
                            in: Capsule()
                        )
                    }
                    .buttonStyle(.plain)
                    .help(showArchivedHighlights ? "Hide archived highlights" : "Show archived highlights")
                }
            }

            if let tagId = appState.highlightTagFilterId,
               let tag = allTags.first(where: { $0.id == tagId }) {
                HStack(spacing: 6) {
                    TagChipView(title: tag.name, isSelected: true) {
                        appState.highlightTagFilterId = nil
                    }

                    Button {
                        appState.highlightTagFilterId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyState: some View {
        let title: String
        if highlights.isEmpty {
            title = "No Highlights Yet"
        } else if showArchivedHighlights {
            title = "No Matching Highlights"
        } else {
            title = "No Current Highlights"
        }

        return VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func deleteHighlight(_ highlight: Highlight) {
        modelContext.delete(highlight)
        try? modelContext.save()
    }

    private func requestArticleRefresh() {
        guard let article = appState.currentArticle else { return }
        appState.pendingHighlightArticleRefresh = AppState.HighlightArticleRefreshRequest(
            id: UUID(),
            articleTitle: article.title
        )
        appState.lastHighlightArticleRefreshResult = nil
    }

    private func archiveStaleHighlights() {
        guard !staleHighlights.isEmpty else { return }
        let staleIDs = Set(staleHighlights.map(\.id.uuidString))
        if let selectedId = appState.selectedHighlightId,
           staleIDs.contains(selectedId) {
            appState.selectedHighlightId = nil
        }
        staleHighlights.forEach { highlight in
            highlight.isArchived = true
            highlight.updatedAt = Date()
        }
        try? modelContext.save()
    }
}
