import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DirectorySnapshotBuilderTests {
    @Test func buildVisibleSnapshotFiltersListByLabelAndTagAndSortsByLength() {
        let label = Label(name: "Research", color: .blue)
        let keepTag = Tag(name: "Keep")

        let short = SavedArticle(title: "Short")
        short.labelId = label.id
        short.wordCount = 120

        let long = SavedArticle(title: "Long")
        long.labelId = label.id
        long.wordCount = 640

        let read = SavedArticle(title: "Read")
        read.labelId = label.id
        read.wordCount = 300
        read.isRead = true

        let otherLabel = SavedArticle(title: "Elsewhere")

        let list = ReadingList(name: "Queue")
        list.articles = [short, long, read, otherLabel]
        list.sortMode = .articleLength
        list.filterMode = .all

        let longState = ArticleState(
            articleTitle: "Long",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Long"))!
        )
        longState.tags = [keepTag]

        let readState = ArticleState(
            articleTitle: "Read",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Read"))!,
            isRead: true
        )
        readState.tags = [keepTag]

        let shortHighlight = Highlight(
            text: "Short",
            articleTitle: "Short",
            startOffset: 0,
            length: 5
        )
        shortHighlight.tags = [keepTag]

        let indexes = DirectoryArticleIndexes(
            articleStates: [longState, readState],
            highlights: [shortHighlight],
            savedArticles: [short, long, read, otherLabel]
        )

        let snapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: list,
            selectedLabel: nil,
            selectedTag: nil,
            rootSelection: .recents,
            recentsScope: .allTabs,
            activeTabId: nil,
            openTabs: [],
            recentArticles: [],
            savedArticles: [short, long, read, otherLabel],
            articleStates: [longState, readState],
            highlights: [shortHighlight],
            localLabelFilter: label,
            localTagFilter: keepTag,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.listArticles.map { $0.title } == ["Long", "Read", "Short"])
        #expect(snapshot.visibleTitles == ["Long", "Read", "Short"])
        #expect(snapshot.visibleReadCount == 1)
        #expect(snapshot.visibleUnreadCount == 2)
    }

    @Test func buildVisibleSnapshotDeduplicatesCurrentTabHistoryByMostRecentOccurrence() {
        let adaFirst = HistoryItem(article: Article(id: "1", title: "Ada Lovelace"))
        let hopper = HistoryItem(article: Article(id: "2", title: "Grace Hopper"))
        let adaAgain = HistoryItem(article: Article(id: "3", title: "Ada Lovelace"))

        let tab = ArticleTab(
            content: .history(
                items: [adaFirst, hopper, adaAgain],
                currentIndex: 2
            )
        )

        let hopperState = ArticleState(
            articleTitle: "Grace Hopper",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Grace_Hopper"))!,
            isRead: true
        )

        let indexes = DirectoryArticleIndexes(
            articleStates: [hopperState],
            highlights: [],
            savedArticles: []
        )

        let snapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: nil,
            selectedLabel: nil,
            selectedTag: nil,
            rootSelection: .recents,
            recentsScope: .currentTab,
            activeTabId: tab.id,
            openTabs: [tab],
            recentArticles: [],
            savedArticles: [],
            articleStates: [hopperState],
            highlights: [],
            localLabelFilter: nil,
            localTagFilter: nil,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.tabHistoryItems.map(\.article.title) == ["Ada Lovelace", "Grace Hopper"])
        #expect(snapshot.visibleTitles == ["Ada Lovelace", "Grace Hopper"])
        #expect(snapshot.visibleReadCount == 1)
        #expect(snapshot.visibleUnreadCount == 1)
    }
}
