import Foundation
import SwiftData

@MainActor
struct ArticleLookupIndex {
    static let empty = ArticleLookupIndex(articleStates: [], savedArticles: [])

    private let articleStateByURL: [String: ArticleState]
    private let articleStateByTitle: [String: ArticleState]
    private let savedArticleByTitle: [String: SavedArticle]
    let savedArticleTitlesNormalized: Set<String>

    init(
        articleStates: [ArticleState],
        savedArticles: [SavedArticle]
    ) {
        articleStateByURL = articleStates.reduce(into: [:]) { result, state in
            result[state.articleURLString] = state
        }

        articleStateByTitle = articleStates.reduce(into: [:]) { result, state in
            result[ReadStateSync.normalizedTitle(state.articleTitle)] = state
        }

        var savedLookup: [String: SavedArticle] = [:]
        var savedTitles = Set<String>()
        savedTitles.reserveCapacity(savedArticles.count)

        for article in savedArticles {
            let key = ReadStateSync.normalizedTitle(article.title)
            savedTitles.insert(key)
            if savedLookup[key] == nil {
                savedLookup[key] = article
            }
        }

        savedArticleByTitle = savedLookup
        savedArticleTitlesNormalized = savedTitles
    }

    init(
        articleStates: [ArticleState] = [],
        readingLists: [ReadingList]
    ) {
        self.init(
            articleStates: articleStates,
            savedArticles: readingLists.flatMap(\.articles)
        )
    }

    func articleState(for title: String) -> ArticleState? {
        let urlString = ReadStateSync.urlString(for: title)
        if let state = articleStateByURL[urlString] {
            return state
        }
        return articleStateByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func savedArticle(for title: String) -> SavedArticle? {
        savedArticleByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func isSaved(title: String) -> Bool {
        savedArticleTitlesNormalized.contains(ReadStateSync.normalizedTitle(title))
    }

    func effectiveReadState(for title: String, fallback: Bool) -> Bool {
        if let state = articleState(for: title) {
            return state.isRead
        }
        if let savedArticle = savedArticle(for: title) {
            return savedArticle.isRead
        }
        return fallback
    }

    static func currentArticleTitleNormalized(in appState: AppState) -> String? {
        guard let activeId = appState.activeTabId,
              let tab = appState.openTabs.first(where: { $0.id == activeId }) else {
            return nil
        }
        return ReadStateSync.normalizedTitle(tab.article.title)
    }
}

@MainActor
func articleLookupIndexFingerprint(
    articleStates: [ArticleState],
    savedArticles: [SavedArticle]
) -> Int {
    var hasher = Hasher()
    hasher.combine(articleStates.count)
    hasher.combine(savedArticles.count)

    for state in articleStates {
        hasher.combine(state.id)
        hasher.combine(state.articleTitle)
        hasher.combine(state.articleURLString)
        hasher.combine(state.isRead)
        hasher.combine(state.readingProgress?.bitPattern)
        hasher.combine(state.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(stableTagFingerprint(for: state.tags))
        hasher.combine(state.labelId)
    }

    for article in savedArticles {
        hasher.combine(article.id)
        hasher.combine(article.title)
        hasher.combine(article.isRead)
        hasher.combine(article.wordCount)
        hasher.combine(article.savedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(article.labelId)
    }

    return hasher.finalize()
}

@MainActor
func articleLookupIndexFingerprint(
    articleStates: [ArticleState] = [],
    readingLists: [ReadingList]
) -> Int {
    var hasher = Hasher()
    hasher.combine(articleStates.count)
    hasher.combine(readingLists.count)

    for state in articleStates {
        hasher.combine(state.id)
        hasher.combine(state.articleTitle)
        hasher.combine(state.articleURLString)
        hasher.combine(state.isRead)
        hasher.combine(state.readingProgress?.bitPattern)
        hasher.combine(state.updatedAt.timeIntervalSinceReferenceDate.bitPattern)
        hasher.combine(stableTagFingerprint(for: state.tags))
        hasher.combine(state.labelId)
    }

    for list in readingLists {
        hasher.combine(list.id)
        hasher.combine(list.articles.count)
        for article in list.articles {
            hasher.combine(article.id)
            hasher.combine(article.title)
            hasher.combine(article.isRead)
            hasher.combine(article.wordCount)
            hasher.combine(article.savedAt.timeIntervalSinceReferenceDate.bitPattern)
            hasher.combine(article.labelId)
        }
    }

    return hasher.finalize()
}

@MainActor
func stableTagFingerprint(for tags: [Tag]) -> Int {
    var hasher = Hasher()
    hasher.combine(tags.count)

    for tag in tags.sorted(by: { lhs, rhs in
        lhs.id.uuidString < rhs.id.uuidString
    }) {
        hasher.combine(tag.id)
        hasher.combine(tag.sortOrder)
    }

    return hasher.finalize()
}
