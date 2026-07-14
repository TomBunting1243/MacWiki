import Foundation
import Testing

@testable import MacWiki

@MainActor
struct TabBarLibraryIndexTests {
    @Test func reusesNormalizedLibrarySnapshotUntilSemanticRevisionChanges() {
        let list = ReadingList(name: "Research")
        let article = SavedArticle(title: " Ada Lovelace ", list: list)
        list.articles = [article]
        let highlight = Highlight(
            text: "Analytical Engine",
            articleTitle: "Ada Lovelace",
            startOffset: 0,
            length: 17
        )
        let index = TabBarLibraryIndex()

        let first = index.snapshot(lists: [list], highlights: [highlight])
        let second = index.snapshot(lists: [list], highlights: [highlight])
        let normalizedTitle = ReadStateSync.normalizedTitle("Ada Lovelace")

        #expect(index.rebuildCount == 1)
        #expect(first.savedArticleByTitle[normalizedTitle] === article)
        #expect(second.savedArticleByTitle[normalizedTitle] === article)
        #expect(first.highlightedTitles == [normalizedTitle])
        #expect(second.highlightedTitles == [normalizedTitle])
    }

    @Test func rebuildsForListAndHighlightRevisions() {
        let list = ReadingList(name: "Research")
        let firstArticle = SavedArticle(title: "Ada Lovelace", list: list)
        list.articles = [firstArticle]
        let highlight = Highlight(
            text: "Analytical Engine",
            articleTitle: "Ada Lovelace",
            startOffset: 0,
            length: 17
        )
        let index = TabBarLibraryIndex()

        _ = index.snapshot(lists: [list], highlights: [highlight])

        let secondArticle = SavedArticle(title: "Charles Babbage", list: list)
        list.articles.append(secondArticle)
        list.updatedAt = list.updatedAt.addingTimeInterval(1)
        let afterListChange = index.snapshot(lists: [list], highlights: [highlight])

        highlight.isArchived = true
        highlight.updatedAt = highlight.updatedAt.addingTimeInterval(1)
        let afterHighlightChange = index.snapshot(lists: [list], highlights: [highlight])

        #expect(index.rebuildCount == 3)
        #expect(afterListChange.savedArticleByTitle.count == 2)
        #expect(afterHighlightChange.highlightedTitles.isEmpty)
    }

    @Test func preservesQueryOrderWhenAnArticleExistsInMultipleLists() {
        let firstList = ReadingList(name: "First")
        let secondList = ReadingList(name: "Second")
        let firstCopy = SavedArticle(title: "Ada Lovelace", list: firstList)
        let secondCopy = SavedArticle(title: "ADA LOVELACE", list: secondList)
        firstList.articles = [firstCopy]
        secondList.articles = [secondCopy]
        let index = TabBarLibraryIndex()

        let snapshot = index.snapshot(
            lists: [firstList, secondList],
            highlights: []
        )
        let normalizedTitle = ReadStateSync.normalizedTitle("Ada Lovelace")

        #expect(snapshot.savedArticleByTitle[normalizedTitle] === firstCopy)
    }
}
