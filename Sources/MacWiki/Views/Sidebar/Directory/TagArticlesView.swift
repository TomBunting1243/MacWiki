import SwiftData
import SwiftUI

struct TagArticlesView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let tag: Tag
    let allTags: [Tag]
    let allLists: [ReadingList]
    let allLabels: [Label]
    let visibleArticles: [Article]
    let articleIndexes: DirectoryArticleIndexes
    let columnState: DirectoryColumnState
    let metadataHydrator: ArticleMetadataHydrator
    let onNewLabelWithArticle: (SavedArticle) -> Void
    let onNewTagWithArticle: (Article) -> Void

    @State private var activePageViewsArticleTitle: String?

    private var localTagFilter: Tag? {
        get { columnState.localTagFilter }
        nonmutating set { columnState.localTagFilter = newValue }
    }

    private func savedArticle(for title: String) -> SavedArticle? {
        articleIndexes.savedArticle(for: title)
    }

    private func readingProgress(for title: String) -> Double {
        articleIndexes.readingProgress(for: title, in: appState)
    }

    private func effectiveReadState(for title: String) -> Bool {
        articleIndexes.effectiveReadState(for: title, fallback: false)
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

    private func isCurrentArticle(_ title: String) -> Bool {
        currentArticleTitleNormalized == ReadStateSync.normalizedTitle(title)
    }

    private func pageViewsPopoverBinding(for articleTitle: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsArticleTitle == articleTitle },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsArticleTitle == articleTitle {
                    activePageViewsArticleTitle = nil
                }
            }
        )
    }

    var body: some View {
        Section {
            if visibleArticles.isEmpty {
                Text("No tagged articles")
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
                    let isRead = effectiveReadState(for: article.title)
                    let progress = readingProgress(for: article.title)
                    let tags = tagsForArticle(title: article.title)
                        .filter { $0.id != tag.id }

                    if let saved = savedArticle(for: article.title) {
                        SavedArticleRow(
                            savedArticle: saved,
                            hydratedMetadata: hydratedMetadata(for: article.title),
                            isRead: isRead,
                            readProgress: progress,
                            isCurrent: isCurrentArticle(article.title),
                            list: saved.readingList,
                            allLists: allLists,
                            allLabels: allLabels,
                            onToggleRead: {
                                ArticleLibraryActions.toggleReadStatus(
                                    for: saved,
                                    effectiveReadState: isRead,
                                    modelContext: modelContext,
                                    appState: appState
                                )
                            },
                            onMove: { targetList in
                                ArticleLibraryActions.moveArticle(
                                    saved,
                                    from: saved.readingList,
                                    to: targetList,
                                    modelContext: modelContext
                                )
                            },
                            onRemove: {
                                ArticleLibraryActions.removeSavedArticle(
                                    saved,
                                    modelContext: modelContext
                                )
                            },
                            tags: tags,
                            allTags: allTags,
                            selectedTagId: localTagFilter?.id,
                            onTagClick: { tag in
                                localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                            },
                            showsListMembership: true,
                            onNewLabel: { draft in
                                onNewLabelWithArticle(draft)
                            },
                            onNewTag: { draft in
                                onNewTagWithArticle(draft)
                            }
                        )
                    } else {
                        ArticleListItem(
                            accessibilityTitle: article.title,
                            isRead: isRead,
                            progress: progress,
                            isCurrent: isCurrentArticle(article.title),
                            onTap: {
                                if SystemBridge.isOptionPressed {
                                    appState.presentOptionClickSavePrompt(for: article)
                                    return
                                }
                                appState.openArticle(article, inNewTab: SystemBridge.isCommandPressed)
                            }
                        ) { isHovered, _ in
                            ArticleRowWithFetch(
                                article: article,
                                hydratedMetadata: hydratedMetadata(for: article.title),
                                isHovered: isHovered,
                                tags: tags,
                                selectedTagId: localTagFilter?.id,
                                onTagClick: { tag in
                                    localTagFilter = (localTagFilter?.id == tag.id) ? nil : tag
                                }
                            )
                        }
                        .contextMenu {
                            ArticleContextMenuContent(
                                article: article,
                                isRead: isRead,
                                currentTags: tags,
                                allLabels: allLabels,
                                allTags: allTags,
                                allLists: allLists,
                                modelContext: modelContext,
                                appState: appState,
                                onNewLabel: { draft in
                                    onNewLabelWithArticle(draft)
                                },
                                onNewTag: { draftArticle in
                                    onNewTagWithArticle(draftArticle)
                                },
                                onShowPageViews: {
                                    activePageViewsArticleTitle = article.title
                                }
                            )
                        }
                        .popover(isPresented: pageViewsPopoverBinding(for: article.title), arrowEdge: .trailing) {
                            SidebarPageViewsPopoverContent(
                                title: article.title,
                                referenceDate: Date()
                            )
                        }
                    }
                }
            }
        }
    }
}
