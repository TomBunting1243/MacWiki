import Foundation

enum DirectoryReadFilter {
    case all
    case unread
}

enum DirectorySupplementalSortMode: String, CaseIterable {
    case recent = "Recent"
    case title = "Title"
    case articleLength = "Length"
}

@MainActor
struct DirectoryArticleIndexes {
    static let empty = DirectoryArticleIndexes(articleStates: [], highlights: [], savedArticles: [])

    private let lookupIndex: ArticleLookupIndex
    private let highlightsByTitle: [String: [Highlight]]

    init(
        articleStates: [ArticleState],
        highlights: [Highlight],
        savedArticles: [SavedArticle] = []
    ) {
        lookupIndex = ArticleLookupIndex(
            articleStates: articleStates,
            savedArticles: savedArticles
        )

        highlightsByTitle = highlights.reduce(into: [:]) { result, highlight in
            let key = ReadStateSync.normalizedTitle(highlight.articleTitle)
            result[key, default: []].append(highlight)
        }
    }

    func articleState(for title: String) -> ArticleState? {
        lookupIndex.articleState(for: title)
    }

    func savedArticle(for title: String) -> SavedArticle? {
        lookupIndex.savedArticle(for: title)
    }

    func cachedHighlights(for title: String) -> [Highlight] {
        highlightsByTitle[ReadStateSync.normalizedTitle(title)] ?? []
    }

    func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        lookupIndex.effectiveReadState(for: title, fallback: fallback)
    }

    func tagsForArticle(title: String) -> [Tag] {
        var seen = Set<UUID>()
        let stateTags = articleState(for: title)?.tags.sorted { $0.sortOrder < $1.sortOrder } ?? []
        let highlightTags = cachedHighlights(for: title).flatMap { $0.tags }
        return (stateTags + highlightTags).filter { tag in
            if seen.contains(tag.id) { return false }
            seen.insert(tag.id)
            return true
        }
    }

    func articleHasTag(_ title: String, tagId: UUID) -> Bool {
        if articleState(for: title)?.tags.contains(where: { $0.id == tagId }) == true {
            return true
        }
        return cachedHighlights(for: title).contains { highlight in
            highlight.tags.contains(where: { $0.id == tagId })
        }
    }

    func readingProgress(for title: String, in appState: AppState) -> Double {
        if isCurrentArticle(title, in: appState), let live = appState.liveReadingProgress(forTitle: title) {
            return live
        }
        return articleState(for: title)?.readingProgress ?? 0
    }

    func isCurrentArticle(_ title: String, in appState: AppState) -> Bool {
        guard let activeTitle = Self.currentArticleTitleNormalized(in: appState) else { return false }
        return activeTitle == ReadStateSync.normalizedTitle(title)
    }

    static func currentArticleTitleNormalized(in appState: AppState) -> String? {
        ArticleLookupIndex.currentArticleTitleNormalized(in: appState)
    }
}

@MainActor
func directoryArticleIndexesFingerprint(
    articleStates: [ArticleState],
    highlights: [Highlight],
    savedArticles: [SavedArticle]
) -> Int {
    var hasher = Hasher()
    hasher.combine(articleLookupIndexFingerprint(
        articleStates: articleStates,
        savedArticles: savedArticles
    ))
    hasher.combine(highlights.count)

    for highlight in highlights {
        hasher.combine(highlight.id)
        hasher.combine(highlight.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(stableTagFingerprint(for: highlight.tags))
        hasher.combine(highlight.isArchivedRaw ?? false)
    }

    return hasher.finalize()
}

@MainActor
struct DirectoryVisibleSnapshot {
    static let empty = DirectoryVisibleSnapshot(
        visibleTitles: [],
        listArticles: [],
        tabHistoryItems: [],
        recentArticles: [],
        visibleReadCount: 0,
        visibleUnreadCount: 0
    )

    let visibleTitles: [String]
    let listArticles: [SavedArticle]
    let tabHistoryItems: [HistoryItem]
    let recentArticles: [Article]
    let visibleReadCount: Int
    let visibleUnreadCount: Int
}
