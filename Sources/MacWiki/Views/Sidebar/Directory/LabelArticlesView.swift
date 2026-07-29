import SwiftData
import SwiftUI

struct LabelArticlesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let labels: [Label]
    let allTags: [Tag]
    let allLists: [ReadingList]
    let visibleArticles: [SavedArticle]
    let articleIndexes: DirectoryArticleIndexes
    let columnState: DirectoryColumnState
    let metadataHydrator: ArticleMetadataHydrator
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    private var localTagFilter: Tag? {
        get { columnState.localTagFilter }
        nonmutating set { columnState.localTagFilter = newValue }
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
    }
}
