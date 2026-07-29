import Foundation

@MainActor
enum DirectorySnapshotBuilder {
    static func buildVisibleSnapshot(
        selectedList: ReadingList?,
        selectedLabel: Label?,
        selectedTag: Tag?,
        rootSelection: SidebarRootSelection,
        recentsScope: RecentsScope,
        activeTabId: UUID?,
        openTabs: [ArticleTab],
        recentArticles: [Article],
        savedArticles: [SavedArticle],
        articleStates: [ArticleState],
        highlights: [Highlight],
        localLabelFilter: Label?,
        localTagFilter: Tag?,
        supplementalReadFilter: DirectoryReadFilter,
        supplementalSortMode: DirectorySupplementalSortMode,
        articleIndexes: DirectoryArticleIndexes,
        resolvedSavedArticleWordCount: (SavedArticle) -> Int,
        resolvedArticleWordCount: (Article) -> Int
    ) -> DirectoryVisibleSnapshot {
        let listArticles: [SavedArticle]
        let labelArticles: [SavedArticle]
        let tagArticles: [Article]
        let tabHistoryItems: [HistoryItem]
        let recentArticlesSnapshot: [Article]
        let visibleTitles: [String]

        if let selectedList {
            listArticles = sortedArticles(
                for: selectedList,
                localLabelFilter: localLabelFilter,
                localTagFilter: localTagFilter,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedSavedArticleWordCount
            )
            labelArticles = []
            tagArticles = []
            tabHistoryItems = []
            recentArticlesSnapshot = []
            visibleTitles = listArticles.map(\.title)
        } else if let selectedLabel {
            listArticles = []
            let labelSnapshot = LabelArticlesSnapshot(
                label: selectedLabel,
                savedArticles: savedArticles,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                tagFilter: localTagFilter,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedSavedArticleWordCount
            )
            labelArticles = labelSnapshot.articles
            tagArticles = []
            tabHistoryItems = []
            recentArticlesSnapshot = []
            visibleTitles = labelSnapshot.visibleTitles
        } else if let selectedTag {
            listArticles = []
            labelArticles = []
            let tagSnapshot = TagArticlesSnapshot(
                tag: selectedTag,
                articleStates: articleStates,
                highlights: highlights,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                tagFilter: localTagFilter,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedArticleWordCount
            )
            tagArticles = tagSnapshot.articles
            tabHistoryItems = []
            recentArticlesSnapshot = []
            visibleTitles = tagSnapshot.visibleTitles
        } else if recentsScope == .currentTab,
                  rootSelection != .discover,
                  let activeTabId,
                  let tab = openTabs.first(where: { $0.id == activeTabId }) {
            listArticles = []
            labelArticles = []
            tagArticles = []
            tabHistoryItems = filteredTabHistoryItems(
                for: tab,
                localTagFilter: localTagFilter,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedArticleWordCount
            )
            recentArticlesSnapshot = []
            visibleTitles = tabHistoryItems.map(\.article.title)
        } else {
            listArticles = []
            labelArticles = []
            tagArticles = []
            tabHistoryItems = []
            recentArticlesSnapshot = filteredRecentArticles(
                recentArticles,
                localTagFilter: localTagFilter,
                readFilter: supplementalReadFilter,
                sortMode: supplementalSortMode,
                articleIndexes: articleIndexes,
                resolvedWordCount: resolvedArticleWordCount
            )
            visibleTitles = recentArticlesSnapshot.map(\.title)
        }

        let visibleReadStates: [Bool]
        if selectedList != nil {
            visibleReadStates = listArticles.map {
                articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
            }
        } else if !tabHistoryItems.isEmpty {
            visibleReadStates = tabHistoryItems.map {
                articleIndexes.effectiveReadState(for: $0.article.title, fallback: $0.article.isRead)
            }
        } else if !recentArticlesSnapshot.isEmpty {
            visibleReadStates = recentArticlesSnapshot.map {
                articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
            }
        } else {
            visibleReadStates = visibleTitles.map {
                articleIndexes.effectiveReadState(for: $0, fallback: false)
            }
        }

        let counts = visibleReadStates.reduce(into: (read: 0, unread: 0)) { result, isRead in
            if isRead {
                result.read += 1
            } else {
                result.unread += 1
            }
        }

        return DirectoryVisibleSnapshot(
            visibleTitles: visibleTitles,
            listArticles: listArticles,
            labelArticles: labelArticles,
            tagArticles: tagArticles,
            tabHistoryItems: tabHistoryItems,
            recentArticles: recentArticlesSnapshot,
            visibleReadCount: counts.read,
            visibleUnreadCount: counts.unread
        )
    }

    static func taggedArticleTitles(
        for tag: Tag,
        articleStates: [ArticleState],
        highlights: [Highlight]
    ) -> [String] {
        TagArticlesSnapshot.titlesByRecency(
            for: tag,
            articleStates: articleStates,
            highlights: highlights
        )
    }

    static func deduplicatedHistory(_ history: [HistoryItem]) -> [HistoryItem] {
        var seen = Set<String>()
        var result: [HistoryItem] = []

        for item in history.reversed() {
            let normalized = ReadStateSync.normalizedTitle(item.article.title)
            guard seen.insert(normalized).inserted else { continue }
            result.append(item)
        }

        return result
    }

    private static func sortedArticles(
        for list: ReadingList,
        localLabelFilter: Label?,
        localTagFilter: Tag?,
        articleIndexes: DirectoryArticleIndexes,
        resolvedWordCount: (SavedArticle) -> Int
    ) -> [SavedArticle] {
        let filtered = filteredArticles(
            for: list,
            localLabelFilter: localLabelFilter,
            localTagFilter: localTagFilter,
            articleIndexes: articleIndexes
        )

        switch list.sortMode {
        case .addedDate:
            return filtered.sorted { $0.savedAt > $1.savedAt }
        case .title:
            return filtered.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .manual:
            return filtered.sorted { $0.manualOrder < $1.manualOrder }
        case .articleLength:
            return filtered.sorted { resolvedWordCount($0) > resolvedWordCount($1) }
        }
    }

    private static func filteredArticles(
        for list: ReadingList,
        localLabelFilter: Label?,
        localTagFilter: Tag?,
        articleIndexes: DirectoryArticleIndexes
    ) -> [SavedArticle] {
        let baseArticles: [SavedArticle] = {
            switch list.filterMode {
            case .all:
                return list.articles
            case .unread:
                return list.articles.filter {
                    !articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
                }
            case .read:
                return list.articles.filter {
                    articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
                }
            }
        }()

        var filtered = baseArticles

        if let localLabelFilter {
            filtered = filtered.filter { $0.labelId == localLabelFilter.id }
        }

        if let localTagFilter {
            filtered = filtered.filter {
                articleIndexes.articleHasTag($0.title, tagId: localTagFilter.id)
            }
        }

        return filtered
    }

    private static func filteredTabHistoryItems(
        for tab: ArticleTab,
        localTagFilter: Tag?,
        readFilter: DirectoryReadFilter,
        sortMode: DirectorySupplementalSortMode,
        articleIndexes: DirectoryArticleIndexes,
        resolvedWordCount: (Article) -> Int
    ) -> [HistoryItem] {
        var scoped = deduplicatedHistory(tab.history)

        if let localTagFilter {
            scoped = scoped.filter {
                articleIndexes.articleHasTag($0.article.title, tagId: localTagFilter.id)
            }
        }

        if readFilter == .unread {
            scoped = scoped.filter {
                !articleIndexes.effectiveReadState(for: $0.article.title, fallback: $0.article.isRead)
            }
        }

        switch sortMode {
        case .recent:
            return scoped
        case .title:
            return scoped.sorted { $0.article.title.localizedCompare($1.article.title) == .orderedAscending }
        case .articleLength:
            return scoped.sorted { resolvedWordCount($0.article) > resolvedWordCount($1.article) }
        }
    }

    private static func filteredRecentArticles(
        _ recentArticles: [Article],
        localTagFilter: Tag?,
        readFilter: DirectoryReadFilter,
        sortMode: DirectorySupplementalSortMode,
        articleIndexes: DirectoryArticleIndexes,
        resolvedWordCount: (Article) -> Int
    ) -> [Article] {
        var scoped = recentArticles

        if let localTagFilter {
            scoped = scoped.filter {
                articleIndexes.articleHasTag($0.title, tagId: localTagFilter.id)
            }
        }

        if readFilter == .unread {
            scoped = scoped.filter {
                !articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
            }
        }

        switch sortMode {
        case .recent:
            return scoped
        case .title:
            return scoped.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            return scoped.sorted { resolvedWordCount($0) > resolvedWordCount($1) }
        }
    }
}
