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

    @Test func buildVisibleSnapshotCountsInMemoryHistoryReadStateWithoutPersistedBacking() {
        let readArticle = Article(id: "read", title: "Read in Memory", isRead: true)
        let unreadArticle = Article(id: "unread", title: "Unread in Memory", isRead: false)
        let tab = ArticleTab(
            content: .history(
                items: [
                    HistoryItem(article: readArticle),
                    HistoryItem(article: unreadArticle)
                ],
                currentIndex: 1
            )
        )
        let indexes = DirectoryArticleIndexes(
            articleStates: [],
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
            articleStates: [],
            highlights: [],
            localLabelFilter: nil,
            localTagFilter: nil,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.visibleTitles == ["Unread in Memory", "Read in Memory"])
        #expect(snapshot.visibleReadCount == 1)
        #expect(snapshot.visibleUnreadCount == 1)
    }

    @Test func buildVisibleSnapshotCountsInMemoryRecentReadStateWithoutPersistedBacking() {
        let readArticle = Article(id: "read", title: "Read Recent", isRead: true)
        let unreadArticle = Article(id: "unread", title: "Unread Recent", isRead: false)
        let indexes = DirectoryArticleIndexes(
            articleStates: [], highlights: [], savedArticles: []
        )

        let snapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: nil,
            selectedLabel: nil,
            selectedTag: nil,
            rootSelection: .recents,
            recentsScope: .allTabs,
            activeTabId: nil,
            openTabs: [],
            recentArticles: [readArticle, unreadArticle],
            savedArticles: [],
            articleStates: [],
            highlights: [],
            localLabelFilter: nil,
            localTagFilter: nil,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.visibleTitles == ["Read Recent", "Unread Recent"])
        #expect(snapshot.visibleReadCount == 1)
        #expect(snapshot.visibleUnreadCount == 1)
    }

    @Test func buildVisibleSnapshotPublishesTheLabelRowsItAlreadyDerived() {
        let label = Label(name: "Research", color: .blue)
        let tag = Tag(name: "Keep")
        let matching = SavedArticle(title: "Matching")
        matching.labelId = label.id
        let filteredOut = SavedArticle(title: "Filtered Out")
        filteredOut.labelId = label.id

        let matchingState = ArticleState(
            articleTitle: matching.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: matching.title))!
        )
        matchingState.tags = [tag]
        let indexes = DirectoryArticleIndexes(
            articleStates: [matchingState],
            highlights: [],
            savedArticles: [matching, filteredOut]
        )

        let snapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: nil,
            selectedLabel: label,
            selectedTag: nil,
            rootSelection: .recents,
            recentsScope: .allTabs,
            activeTabId: nil,
            openTabs: [],
            recentArticles: [],
            savedArticles: [matching, filteredOut],
            articleStates: [matchingState],
            highlights: [],
            localLabelFilter: nil,
            localTagFilter: tag,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.labelArticles.map { $0.title } == ["Matching"])
        #expect(snapshot.tagArticles.isEmpty)
        #expect(snapshot.visibleTitles == ["Matching"])
    }

    @Test func buildVisibleSnapshotPublishesTheTagRowsItAlreadyDerived() {
        let tag = Tag(name: "Archive")
        let saved = SavedArticle(title: "Saved Tagged Article")
        let state = ArticleState(
            articleTitle: saved.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: saved.title))!
        )
        state.tags = [tag]
        let indexes = DirectoryArticleIndexes(
            articleStates: [state],
            highlights: [],
            savedArticles: [saved]
        )

        let snapshot = DirectorySnapshotBuilder.buildVisibleSnapshot(
            selectedList: nil,
            selectedLabel: nil,
            selectedTag: tag,
            rootSelection: .recents,
            recentsScope: .allTabs,
            activeTabId: nil,
            openTabs: [],
            recentArticles: [],
            savedArticles: [saved],
            articleStates: [state],
            highlights: [],
            localLabelFilter: nil,
            localTagFilter: nil,
            supplementalReadFilter: .all,
            supplementalSortMode: .recent,
            articleIndexes: indexes,
            resolvedSavedArticleWordCount: { $0.wordCount ?? 0 },
            resolvedArticleWordCount: { $0.wordCount ?? 0 }
        )

        #expect(snapshot.labelArticles.isEmpty)
        #expect(snapshot.tagArticles.map { $0.title } == [saved.title])
        #expect(snapshot.visibleTitles == [saved.title])
    }

    @Test func snapshotPublicationNeverLeaksRowsAcrossDirectoryScopes() {
        let article = Article(id: "ada", title: "Ada Lovelace")
        let snapshot = DirectoryVisibleSnapshot(
            visibleTitles: [article.title],
            listArticles: [],
            labelArticles: [],
            tagArticles: [],
            tabHistoryItems: [],
            recentArticles: [article],
            visibleReadCount: 0,
            visibleUnreadCount: 1
        )

        #expect(
            DirectorySnapshotPublication.visibleSnapshot(
                snapshot,
                publishedScopeKey: "root:recents:allTabs",
                requestedScopeKey: "root:recents:allTabs"
            ).visibleTitles == [article.title]
        )
        #expect(
            DirectorySnapshotPublication.visibleSnapshot(
                snapshot,
                publishedScopeKey: "root:recents:allTabs",
                requestedScopeKey: "label:research"
            ).visibleTitles.isEmpty
        )
        #expect(
            DirectorySnapshotPublication.visibleSnapshot(
                snapshot,
                publishedScopeKey: nil,
                requestedScopeKey: "root:recents:allTabs"
            ).visibleTitles.isEmpty
        )
    }
}
