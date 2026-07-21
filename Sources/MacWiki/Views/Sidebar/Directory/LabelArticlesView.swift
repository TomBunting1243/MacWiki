import SwiftData
import SwiftUI

struct LabelArticlesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let label: Label
    let labels: [Label]
    let allTags: [Tag]
    let allLists: [ReadingList]
    let savedArticles: [SavedArticle]
    let articleStates: [ArticleState]
    let highlights: [Highlight]
    let readFilter: DirectoryReadFilter
    let sortMode: DirectorySupplementalSortMode
    let metadataHydrator: ArticleMetadataHydrator
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    @State private var localTagFilter: Tag? = nil
    @State private var articleIndexesSnapshot = DirectoryArticleIndexes.empty
    @State private var visibleSnapshot = LabelArticlesSnapshot.empty

    private var articleIndexes: DirectoryArticleIndexes {
        articleIndexesSnapshot
    }

    private var articleIndexesFingerprint: Int {
        directoryArticleIndexesFingerprint(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private var visibleArticles: [SavedArticle] {
        visibleSnapshot.articles
    }

    private var visibleSnapshotCandidateTitles: [String] {
        savedArticles
            .filter { $0.labelId == label.id }
            .map(\.title)
    }

    private var visibleSnapshotFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(articleIndexesFingerprint)
        hasher.combine(label.id)
        hasher.combine(readFilter == .unread)
        hasher.combine(sortMode.rawValue)
        hasher.combine(localTagFilter?.id)
        for id in allTags.map(\.id).sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }

        if sortMode == .articleLength {
            for title in visibleSnapshotCandidateTitles {
                hasher.combine(ReadStateSync.normalizedTitle(title))
                hasher.combine(metadataHydrator.snapshot(for: title)?.wordCount)
            }
        }

        return hasher.finalize()
    }

    private func refreshArticleIndexesSnapshot() {
        articleIndexesSnapshot = DirectoryArticleIndexes(
            articleStates: articleStates,
            highlights: highlights,
            savedArticles: savedArticles
        )
    }

    private func refreshVisibleSnapshot() {
        let resolvedTagFilter = localTagFilter.flatMap { filter in
            allTags.contains(where: { $0.id == filter.id }) ? filter : nil
        }
        if localTagFilter != nil && resolvedTagFilter == nil {
            localTagFilter = nil
        }

        visibleSnapshot = LabelArticlesSnapshot(
            label: label,
            savedArticles: savedArticles,
            readFilter: readFilter,
            sortMode: sortMode,
            tagFilter: resolvedTagFilter,
            articleIndexes: articleIndexes,
            resolvedWordCount: resolvedWordCount(for:)
        )
    }

    private func readingProgress(for title: String) -> Double {
        articleIndexes.readingProgress(for: title, in: appState)
    }

    private func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        articleIndexes.effectiveReadState(for: title, fallback: fallback)
    }

    private func tagsForArticle(title: String) -> [Tag] {
        articleIndexes.tagsForArticle(title: title)
    }

    private func hydratedMetadata(for title: String) -> ArticleMetadataHydrationSnapshot? {
        metadataHydrator.snapshot(for: title)
    }

    private func resolvedWordCount(for savedArticle: SavedArticle) -> Int {
        metadataHydrator.resolvedWordCount(for: savedArticle)
    }

    private var currentArticleTitleNormalized: String? {
        DirectoryArticleIndexes.currentArticleTitleNormalized(in: appState)
    }

    private func toggleReadStatus(_ article: SavedArticle) {
        ArticleLibraryActions.toggleReadStatus(
            for: article,
            effectiveReadState: effectiveReadState(for: article.title, fallback: article.isRead),
            modelContext: modelContext,
            appState: appState
        )
    }

    private func removeSavedArticle(_ article: SavedArticle) {
        ArticleLibraryActions.removeSavedArticle(article, modelContext: modelContext)
    }

    var body: some View {
        Section {
            if visibleArticles.isEmpty {
                Text("No articles")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                if let localTagFilter {
                    HStack(spacing: 6) {
                        TagChipView(title: localTagFilter.name, isSelected: true)

                        Button {
                            self.localTagFilter = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear tag filter")
                    }
                    .padding(.vertical, 4)
                }

                ForEach(visibleArticles) { article in
                    let isRead = effectiveReadState(for: article.title, fallback: article.isRead)
                    let progress = readingProgress(for: article.title)
                    let tags = tagsForArticle(title: article.title)
                    let isCurrent = currentArticleTitleNormalized == ReadStateSync.normalizedTitle(article.title)

                    SavedArticleRow(
                        savedArticle: article,
                        hydratedMetadata: hydratedMetadata(for: article.title),
                        isRead: isRead,
                        readProgress: progress,
                        isCurrent: isCurrent,
                        list: article.readingList,
                        allLists: allLists,
                        allLabels: labels,
                        onToggleRead: {
                            toggleReadStatus(article)
                        },
                        onMove: { targetList in
                            ArticleLibraryActions.moveArticle(
                                article,
                                from: article.readingList,
                                to: targetList,
                                modelContext: modelContext
                            )
                        },
                        onRemove: { removeSavedArticle(article) },
                        tags: tags,
                        allTags: allTags,
                        selectedTagId: localTagFilter?.id,
                        onTagClick: { tag in
                            localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                        },
                        showsLabelMetadata: false,
                        showsListMembership: true,
                        onNewLabel: { draft in
                            onNewLabelWithArticle(draft)
                        },
                        onNewTag: { draft in
                            onNewTagWithArticle(draft)
                        }
                    )
                }
            }
        }
        .task(id: articleIndexesFingerprint) {
            await Task.yield()
            refreshArticleIndexesSnapshot()
        }
        .task(id: visibleSnapshotFingerprint) {
            await Task.yield()
            refreshVisibleSnapshot()
        }
    }
}
