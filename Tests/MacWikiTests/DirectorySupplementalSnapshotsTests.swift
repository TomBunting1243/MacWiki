import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DirectorySupplementalSnapshotsTests {
    @Test func labelSnapshotAppliesUnreadTagAndLengthSorting() {
        let label = Label(name: "Research", color: .blue)
        let tag = Tag(name: "Important")

        let short = SavedArticle(title: "Short")
        short.labelId = label.id
        short.wordCount = 120

        let long = SavedArticle(title: "Long")
        long.labelId = label.id
        long.wordCount = 640

        let read = SavedArticle(title: "Read")
        read.labelId = label.id
        read.wordCount = 300

        let unrelated = SavedArticle(title: "Elsewhere")

        let longState = ArticleState(
            articleTitle: "Long",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Long"))!
        )
        longState.tags = [tag]
        longState.updatedAt = Date(timeIntervalSinceReferenceDate: 200)

        let readState = ArticleState(
            articleTitle: "Read",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Read"))!,
            isRead: true
        )
        readState.tags = [tag]
        readState.updatedAt = Date(timeIntervalSinceReferenceDate: 201)

        let shortHighlight = Highlight(
            text: "Short",
            articleTitle: "Short",
            startOffset: 0,
            length: 5
        )
        shortHighlight.tags = [tag]

        let indexes = DirectoryArticleIndexes(
            articleStates: [longState, readState],
            highlights: [shortHighlight],
            savedArticles: [short, long, read, unrelated]
        )

        let snapshot = LabelArticlesSnapshot(
            label: label,
            savedArticles: [short, long, read, unrelated],
            readFilter: .unread,
            sortMode: .articleLength,
            tagFilter: tag,
            articleIndexes: indexes,
            resolvedWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.articles.map(\.title) == ["Long", "Short"])
        #expect(snapshot.visibleTitles == ["Long", "Short"])
    }

    @Test func tagSnapshotKeepsRecencyOrderAndPrefersSavedArticleData() {
        let tag = Tag(name: "Archive")

        let saved = SavedArticle(title: "Article One")
        saved.wordCount = 410
        saved.extract = "Saved extract"

        let olderHighlight = Highlight(
            text: "One",
            articleTitle: "Article One",
            startOffset: 0,
            length: 3
        )
        olderHighlight.tags = [tag]
        olderHighlight.createdAt = Date(timeIntervalSinceReferenceDate: 100)

        let newerState = ArticleState(
            articleTitle: "Article Two",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Article Two"))!
        )
        newerState.tags = [tag]
        newerState.updatedAt = Date(timeIntervalSinceReferenceDate: 200)

        let indexes = DirectoryArticleIndexes(
            articleStates: [newerState],
            highlights: [olderHighlight],
            savedArticles: [saved]
        )

        let snapshot = TagArticlesSnapshot(
            tag: tag,
            articleStates: [newerState],
            highlights: [olderHighlight],
            readFilter: .all,
            sortMode: .recent,
            tagFilter: nil,
            articleIndexes: indexes,
            resolvedWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.articles.map(\.title) == ["Article Two", "Article One"])
        #expect(snapshot.articles.last?.wordCount == 410)
        #expect(snapshot.articles.last?.extract == "Saved extract")
    }
}
