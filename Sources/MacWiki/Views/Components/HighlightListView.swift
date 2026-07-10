import SwiftUI
import SwiftData

struct HighlightListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

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
        HighlightDisplayFilter.visibleHighlights(
            from: highlights,
            showStaleHighlights: showStaleHighlights,
            showArchivedHighlights: showArchivedHighlights
        )
    }

    private enum Metrics {
        static let topChromeReservation: CGFloat = 58
        static let horizontalPadding: CGFloat = 16
        static let topPadding: CGFloat = 8
    }

    var body: some View {
        ZStack(alignment: .top) {
            if visibleHighlights.isEmpty {
                emptyState
                    .padding(.top, Metrics.topChromeReservation)
                    .padding(.horizontal, Metrics.horizontalPadding)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(visibleHighlights, id: \.id) { highlight in
                                HighlightRowView(
                                    highlight: highlight,
                                    onDelete: {
                                        withAnimation(.easeOut(duration: 0.2)) {
                                            deleteHighlight(highlight)
                                        }
                                    }
                                )
                                .id(highlight.id)
                            }
                        }
                        .padding(.top, Metrics.topChromeReservation)
                        .padding(.horizontal, Metrics.horizontalPadding)
                        .padding(.bottom, 12)
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

            header
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.top, Metrics.topPadding)
                .zIndex(1)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
        HStack(spacing: 10) {
            Image(systemName: "highlighter")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            Text("Highlights")
                .font(MacWikiTypography.inspectorSectionLabel)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("\(visibleHighlights.count)")
                .font(MacWikiTypography.compactRowMetadata)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor, in: Capsule())

            Spacer(minLength: 6)

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
                            .font(MacWikiTypography.compactRowMetadata)
                        Text("Stale")
                            .font(MacWikiTypography.compactRowMetadata)
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
                            .font(MacWikiTypography.compactRowMetadata)
                        Text("Archived")
                            .font(MacWikiTypography.compactRowMetadata)
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.68 : 0.54)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.035), lineWidth: 0.5)
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
                .font(MacWikiTypography.settingsHelp)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    private func deleteHighlight(_ highlight: Highlight) {
        modelContext.delete(highlight)
        modelContext.saveReportingFailure(operation: #function)
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
        modelContext.saveReportingFailure(operation: #function)
    }
}
