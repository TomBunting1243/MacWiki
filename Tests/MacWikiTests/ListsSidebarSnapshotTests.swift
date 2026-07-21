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

    @Test func fingerprintIsInvariantToQueryOrdering() {
        let area = Area(name: "Research")
        let secondArea = Area(name: "Archive")
        let list = ReadingList(name: "Inbox")
        list.areaId = area.id
        let secondList = ReadingList(name: "Later")
        secondList.areaId = secondArea.id
        let label = Label(name: "Pinned", color: .blue)
        let secondLabel = Label(name: "Filed", color: .gray)
        let tag = Tag(name: "Reference")
        let secondTag = Tag(name: "History")
        let savedArticle = SavedArticle(title: "Article")
        savedArticle.labelId = label.id
        let secondSavedArticle = SavedArticle(title: "Second Article")
        secondSavedArticle.labelId = secondLabel.id
        let highlight = Highlight(text: "Quote", articleTitle: "Article", startOffset: 0, length: 5)
        highlight.tags = [tag, secondTag]
        let secondHighlight = Highlight(
            text: "Second", articleTitle: "Second Article", startOffset: 0, length: 6
        )
        secondHighlight.tags = [secondTag]
        let state = ArticleState(
            articleTitle: "Article",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Article"))!
        )
        state.tags = [tag, secondTag]
        let secondState = ArticleState(
            articleTitle: "Second Article",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Second Article"))!
        )
        secondState.tags = [secondTag]

        let forward = listsSidebarSnapshotFingerprint(
            lists: [list, secondList], areas: [area, secondArea],
            labels: [label, secondLabel], tags: [tag, secondTag],
            savedArticles: [savedArticle, secondSavedArticle],
            highlights: [highlight, secondHighlight], articleStates: [state, secondState],
            sortOrder: .updatedDate
        )
        highlight.tags.reverse()
        state.tags.reverse()
        let reversed = listsSidebarSnapshotFingerprint(
            lists: [secondList, list], areas: [secondArea, area],
            labels: [secondLabel, label], tags: [secondTag, tag],
            savedArticles: [secondSavedArticle, savedArticle],
            highlights: [secondHighlight, highlight], articleStates: [secondState, state],
            sortOrder: .updatedDate
        )

        #expect(forward == reversed)
    }

    @Test func equalPrimarySortKeysUseStableNameAndIdentityTieBreakers() {
        let sharedDate = Date(timeIntervalSinceReferenceDate: 100)
        let alpha = ReadingList(name: "Alpha")
        alpha.createdAt = sharedDate
        alpha.updatedAt = sharedDate
        let beta = ReadingList(name: "Beta")
        beta.createdAt = sharedDate
        beta.updatedAt = sharedDate

        for order in [ListSortOrder.name, .createdDate, .updatedDate, .articleCount] {
            let snapshot = ListsSidebarSnapshot(
                lists: [beta, alpha], areas: [], labels: [], tags: [], savedArticles: [],
                highlights: [], articleStates: [], sortOrder: order
            )
            #expect(snapshot.sortedLists.map(\.id) == [alpha.id, beta.id])
        }

        let firstID = ReadingList(name: "Same")
        firstID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        firstID.createdAt = sharedDate
        firstID.updatedAt = sharedDate
        let secondID = ReadingList(name: "Same")
        secondID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        secondID.createdAt = sharedDate
        secondID.updatedAt = sharedDate
        let identitySnapshot = ListsSidebarSnapshot(
            lists: [secondID, firstID], areas: [], labels: [], tags: [], savedArticles: [],
            highlights: [], articleStates: [], sortOrder: .name
        )
        #expect(identitySnapshot.sortedLists.map(\.id) == [firstID.id, secondID.id])
    }

    @Test func areaListCountsBreakCyclesAndCountEachReachableAreaOnce() {
        let areaA = Area(name: "A")
        let areaB = Area(name: "B", parentId: areaA.id)
        areaA.parentId = areaB.id
        let listA = ReadingList(name: "A List")
        listA.areaId = areaA.id
        let listB = ReadingList(name: "B List")
        listB.areaId = areaB.id

        let snapshot = ListsSidebarSnapshot(
            lists: [listA, listB], areas: [areaA, areaB], labels: [], tags: [],
            savedArticles: [], highlights: [], articleStates: [], sortOrder: .manual
        )

        #expect(snapshot.totalListCount(in: areaA) == 2)
        #expect(snapshot.totalListCount(in: areaB) == 2)
    }
}
