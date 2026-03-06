import Foundation

@MainActor
struct LabelArticlesSnapshot {
    static let empty = LabelArticlesSnapshot(articles: [])

    let articles: [SavedArticle]
    let visibleTitles: [String]

    init(articles: [SavedArticle]) {
        self.articles = articles
        self.visibleTitles = articles.map(\.title)
    }

    init(
        label: Label,
        savedArticles: [SavedArticle],
        readFilter: DirectoryReadFilter,
        sortMode: DirectorySupplementalSortMode,
        tagFilter: Tag?,
        articleIndexes: DirectoryArticleIndexes,
        resolvedWordCount: (SavedArticle) -> Int
    ) {
        var scoped = savedArticles.filter { $0.labelId == label.id }

        if readFilter == .unread {
            scoped = scoped.filter {
                !articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
            }
        }

        if let tagFilter {
            scoped = scoped.filter {
                articleIndexes.articleHasTag($0.title, tagId: tagFilter.id)
            }
        }

        switch sortMode {
        case .recent:
            scoped.sort { $0.savedAt > $1.savedAt }
        case .title:
            scoped.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            scoped.sort { resolvedWordCount($0) > resolvedWordCount($1) }
        }

        self.init(articles: scoped)
    }
}

@MainActor
struct TagArticlesSnapshot {
    static let empty = TagArticlesSnapshot(articles: [])

    let articles: [Article]
    let visibleTitles: [String]

    init(articles: [Article]) {
        self.articles = articles
        self.visibleTitles = articles.map(\.title)
    }

    init(
        tag: Tag,
        articleStates: [ArticleState],
        highlights: [Highlight],
        readFilter: DirectoryReadFilter,
        sortMode: DirectorySupplementalSortMode,
        tagFilter: Tag?,
        articleIndexes: DirectoryArticleIndexes,
        resolvedWordCount: (Article) -> Int
    ) {
        var scoped = Self.titlesByRecency(
            for: tag,
            articleStates: articleStates,
            highlights: highlights
        ).map { title in
            if let saved = articleIndexes.savedArticle(for: title) {
                return Article(
                    id: saved.title,
                    title: saved.title,
                    description: saved.articleDescription,
                    extract: saved.extract,
                    thumbnailURL: saved.thumbnailURL,
                    wordCount: saved.wordCount
                )
            }

            return Article(id: title, title: title)
        }

        if readFilter == .unread {
            scoped = scoped.filter {
                !articleIndexes.effectiveReadState(for: $0.title, fallback: $0.isRead)
            }
        }

        if let tagFilter {
            scoped = scoped.filter {
                articleIndexes.articleHasTag($0.title, tagId: tagFilter.id)
            }
        }

        switch sortMode {
        case .recent:
            break
        case .title:
            scoped.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .articleLength:
            scoped.sort { resolvedWordCount($0) > resolvedWordCount($1) }
        }

        self.init(articles: scoped)
    }

    static func titlesByRecency(
        for tag: Tag,
        articleStates: [ArticleState],
        highlights: [Highlight]
    ) -> [String] {
        var latestByTitle: [String: Date] = [:]
        var displayTitleByKey: [String: String] = [:]

        for highlight in highlights where highlight.tags.contains(where: { $0.id == tag.id }) {
            let key = ReadStateSync.normalizedTitle(highlight.articleTitle)
            guard !key.isEmpty else { continue }
            let current = latestByTitle[key] ?? .distantPast
            if highlight.createdAt > current {
                latestByTitle[key] = highlight.createdAt
                displayTitleByKey[key] = highlight.articleTitle
            }
        }

        for state in articleStates where state.tags.contains(where: { $0.id == tag.id }) {
            let key = ReadStateSync.normalizedTitle(state.articleTitle)
            guard !key.isEmpty else { continue }
            let current = latestByTitle[key] ?? .distantPast
            if state.updatedAt > current {
                latestByTitle[key] = state.updatedAt
                displayTitleByKey[key] = state.articleTitle
            }
        }

        return latestByTitle
            .sorted { $0.value > $1.value }
            .compactMap { key, _ in displayTitleByKey[key] }
    }
}
