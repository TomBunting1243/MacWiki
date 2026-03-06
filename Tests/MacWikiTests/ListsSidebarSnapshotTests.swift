import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ListsSidebarSnapshotTests {
    @Test func snapshotGroupsListsIntoRootAndAreaBuckets() {
        let rootArea = Area(name: "Research")
        rootArea.sortOrder = 0
        rootArea.createdAt = Date(timeIntervalSinceReferenceDate: 100)

        let childArea = Area(name: "Swift", parentId: rootArea.id)
        childArea.sortOrder = 0
        childArea.createdAt = Date(timeIntervalSinceReferenceDate: 101)

        let rootList = ReadingList(name: "Inbox")
        rootList.sortOrder = 0
        rootList.createdAt = Date(timeIntervalSinceReferenceDate: 120)

        let areaList = ReadingList(name: "Benchmarks")
        areaList.sortOrder = 1
        areaList.areaId = rootArea.id
        areaList.createdAt = Date(timeIntervalSinceReferenceDate: 121)

        let childList = ReadingList(name: "Runtime")
        childList.sortOrder = 2
        childList.areaId = childArea.id
        childList.createdAt = Date(timeIntervalSinceReferenceDate: 122)

        let snapshot = ListsSidebarSnapshot(
            lists: [childList, rootList, areaList],
            areas: [childArea, rootArea],
            labels: [],
            tags: [],
            savedArticles: [],
            highlights: [],
            articleStates: [],
            sortOrder: .manual
        )

        #expect(snapshot.rootAreas.map(\.id) == [rootArea.id])
        #expect(snapshot.childAreas(of: rootArea).map(\.id) == [childArea.id])
        #expect(snapshot.rootLevelLists.map(\.id) == [rootList.id])
        #expect(snapshot.lists(in: rootArea).map(\.id) == [areaList.id])
        #expect(snapshot.lists(in: childArea).map(\.id) == [childList.id])
        #expect(snapshot.areaIndexByID[rootArea.id]?.name == "Research")
        #expect(snapshot.parentAreaByID[childArea.id] == rootArea.id)
    }

    @Test func snapshotBuildsStableLabelAndTagCounts() {
        let labelA = Label(name: "Pinned", color: .blue)
        labelA.sortOrder = 1
        let labelB = Label(name: "Archive", color: .gray)
        labelB.sortOrder = 0

        let tagA = Tag(name: "Important")
        tagA.sortOrder = 1
        let tagB = Tag(name: "Reference")
        tagB.sortOrder = 0

        let savedOne = SavedArticle(title: "Article One")
        savedOne.labelId = labelA.id
        let savedTwo = SavedArticle(title: "Article Two")
        savedTwo.labelId = labelA.id

        let highlightOne = Highlight(
            text: "One",
            articleTitle: "Article One",
            startOffset: 0,
            length: 3
        )
        highlightOne.tags = [tagA]

        let highlightTwo = Highlight(
            text: "Two",
            articleTitle: "Article Two",
            startOffset: 0,
            length: 3
        )
        highlightTwo.tags = [tagA]

        let articleState = ArticleState(
            articleTitle: "Article One",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Article One"))!
        )
        articleState.tags = [tagA, tagB]

        let snapshot = ListsSidebarSnapshot(
            lists: [],
            areas: [],
            labels: [labelA, labelB],
            tags: [tagA, tagB],
            savedArticles: [savedOne, savedTwo],
            highlights: [highlightOne, highlightTwo],
            articleStates: [articleState],
            sortOrder: .updatedDate
        )

        #expect(snapshot.sortedLabels.map(\.id) == [labelB.id, labelA.id])
        #expect(snapshot.labelArticleCounts[labelA.id] == 2)
        #expect(snapshot.labelArticleCounts[labelB.id] == nil)

        #expect(snapshot.sortedTags.map(\.id) == [tagB.id, tagA.id])
        #expect(snapshot.tagArticleCounts[tagA.id] == 2)
        #expect(snapshot.tagArticleCounts[tagB.id] == 1)
    }
}
