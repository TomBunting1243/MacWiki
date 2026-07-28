import Foundation
import Testing

@testable import MacWiki

/// Behavioral coverage for the directory's visible-snapshot invalidation boundary.
@MainActor
struct DirectoryFingerprintTests {
    // MARK: - Inputs that must invalidate

    @Test func changingTheSelectedListInvalidates() {
        let inbox = ReadingList(name: "Inbox")
        let archive = ReadingList(name: "Archive")

        let before = DirectoryFingerprint.visible(makeInputs(selectedList: inbox))
        let after = DirectoryFingerprint.visible(makeInputs(selectedList: archive))

        #expect(before != after)
    }

    @Test func changingAListsSortOrFilterModeInvalidates() {
        let list = ReadingList(name: "Inbox")
        let before = DirectoryFingerprint.visible(makeInputs(selectedList: list))

        list.sortMode = .articleLength
        let afterSort = DirectoryFingerprint.visible(makeInputs(selectedList: list))
        #expect(before != afterSort)

        list.filterMode = .unread
        let afterFilter = DirectoryFingerprint.visible(makeInputs(selectedList: list))
        #expect(afterSort != afterFilter)
    }

    @Test func addingOrReorderingSelectedListArticlesInvalidates() {
        let list = ReadingList(name: "Inbox")
        let first = SavedArticle(title: "Swift")
        let second = SavedArticle(title: "Rust")
        first.manualOrder = 0
        second.manualOrder = 1
        list.articles = [first]

        let beforeAdding = DirectoryFingerprint.visible(makeInputs(selectedList: list))
        list.articles.append(second)
        let afterAdding = DirectoryFingerprint.visible(makeInputs(selectedList: list))
        #expect(beforeAdding != afterAdding)

        first.manualOrder = 1
        second.manualOrder = 0
        #expect(afterAdding != DirectoryFingerprint.visible(makeInputs(selectedList: list)))
    }

    @Test func changingTheSelectedLabelsMembershipInvalidates() {
        let label = Label(name: "Research")
        let article = SavedArticle(title: "Swift")
        let before = DirectoryFingerprint.visible(makeInputs(
            selectedLabel: label,
            savedArticles: [article]
        ))

        article.labelId = label.id

        #expect(before != DirectoryFingerprint.visible(makeInputs(
            selectedLabel: label,
            savedArticles: [article]
        )))
    }

    @Test func changingTheSelectedTagsMembershipInvalidates() {
        let tag = Tag(name: "Languages")
        let state = ArticleState(
            articleTitle: "Swift",
            articleURL: URL(fileURLWithPath: "/wiki/Swift")
        )
        let before = DirectoryFingerprint.visible(makeInputs(
            selectedTag: tag,
            articleStates: [state]
        ))

        state.tags = [tag]

        #expect(before != DirectoryFingerprint.visible(makeInputs(
            selectedTag: tag,
            articleStates: [state]
        )))
    }

    @Test func availableLabelAndTagMembershipInvalidates() {
        let labelID = UUID()
        let tagID = UUID()
        let base = DirectoryFingerprint.visible(makeInputs())

        #expect(base != DirectoryFingerprint.visible(makeInputs(availableLabelIDs: [labelID])))
        #expect(base != DirectoryFingerprint.visible(makeInputs(availableTagIDs: [tagID])))
    }

    @Test func supplementalFilterAndSortChangesInvalidate() {
        let base = DirectoryFingerprint.visible(makeInputs())
        let unread = DirectoryFingerprint.visible(makeInputs(supplementalReadFilter: .unread))
        let byLength = DirectoryFingerprint.visible(makeInputs(supplementalSortMode: .articleLength))

        #expect(base != unread)
        #expect(base != byLength)
        #expect(unread != byLength)
    }

    @Test func switchingRootSelectionOrRecentsScopeInvalidates() {
        let base = DirectoryFingerprint.visible(makeInputs())
        let discover = DirectoryFingerprint.visible(makeInputs(rootSelection: .discover))
        let currentTabScope = DirectoryFingerprint.visible(makeInputs(recentsScope: .currentTab))

        #expect(base != discover)
        #expect(base != currentTabScope)
    }

    @Test func currentTabHistoryChangesInvalidateWhenScopedToTheCurrentTab() {
        let tabID = UUID()
        let history = [historyItem(title: "Swift"), historyItem(title: "Rust")]

        let before = DirectoryFingerprint.visible(makeInputs(
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 1
        ))
        let afterNavigatingBack = DirectoryFingerprint.visible(makeInputs(
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 0
        ))

        #expect(before != afterNavigatingBack)
    }

    @Test func discoverPreservesTheExistingCurrentTabInvalidationScope() {
        let tabID = UUID()
        let history = [historyItem(title: "Swift"), historyItem(title: "Rust")]
        let before = DirectoryFingerprint.visible(makeInputs(
            rootSelection: .discover,
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 1
        ))
        let afterNavigatingBack = DirectoryFingerprint.visible(makeInputs(
            rootSelection: .discover,
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 0
        ))

        #expect(before != afterNavigatingBack)
    }

    @Test func globalRecentsChangesInvalidateWhenNoScopeOverridesThem() {
        let before = DirectoryFingerprint.visible(makeInputs(recentArticles: [article("Swift")]))
        let after = DirectoryFingerprint.visible(makeInputs(
            recentArticles: [article("Swift"), article("Rust")]
        ))

        #expect(before != after)
    }

    @Test func upstreamIndexChangesInvalidate() {
        let before = DirectoryFingerprint.visible(makeInputs(articleIndexesFingerprint: 1))
        let after = DirectoryFingerprint.visible(makeInputs(articleIndexesFingerprint: 2))

        #expect(before != after)
    }

    // MARK: - Inputs that must not invalidate

    @Test func identicalInputsProduceAStableFingerprint() {
        let list = ReadingList(name: "Inbox")
        list.articles = [SavedArticle(title: "Swift")]
        let inputs = makeInputs(selectedList: list)

        #expect(DirectoryFingerprint.visible(inputs) == DirectoryFingerprint.visible(inputs))
    }

    @Test func availableCollectionOrderDoesNotInvalidate() {
        let firstLabelID = UUID()
        let secondLabelID = UUID()
        let firstTagID = UUID()
        let secondTagID = UUID()

        let forward = makeInputs(
            availableLabelIDs: [firstLabelID, secondLabelID],
            availableTagIDs: [firstTagID, secondTagID]
        )
        let reversed = makeInputs(
            availableLabelIDs: [secondLabelID, firstLabelID],
            availableTagIDs: [secondTagID, firstTagID]
        )

        #expect(DirectoryFingerprint.visible(forward) == DirectoryFingerprint.visible(reversed))
    }

    @Test func currentTabHistoryIsIgnoredWhenRecentsAreNotScopedToTheCurrentTab() {
        let base = makeInputs(recentsScope: .allTabs, recentArticles: [article("Swift")])
        let withHistory = makeInputs(
            recentsScope: .allTabs,
            activeTabID: UUID(),
            activeTabHistory: [historyItem(title: "Rust")],
            activeTabCurrentIndex: 0,
            recentArticles: [article("Swift")]
        )

        #expect(DirectoryFingerprint.visible(base) == DirectoryFingerprint.visible(withHistory))
    }

    @Test func selectedListScopeIgnoresRecentsAndHistory() {
        let list = ReadingList(name: "Inbox")
        list.articles = [SavedArticle(title: "Swift")]
        let base = makeInputs(
            recentsScope: .currentTab,
            selectedList: list,
            recentArticles: [article("One")]
        )
        let unrelatedChanges = makeInputs(
            recentsScope: .currentTab,
            selectedList: list,
            activeTabID: UUID(),
            activeTabHistory: [historyItem(title: "Two")],
            activeTabCurrentIndex: 0,
            recentArticles: [article("Three")]
        )

        #expect(DirectoryFingerprint.visible(base) == DirectoryFingerprint.visible(unrelatedChanges))
    }

    @Test func resolvedCurrentTabScopeIgnoresGlobalRecents() {
        let tabID = UUID()
        let history = [historyItem(title: "Swift")]
        let before = makeInputs(
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 0,
            recentArticles: [article("One")]
        )
        let after = makeInputs(
            recentsScope: .currentTab,
            activeTabID: tabID,
            activeTabHistory: history,
            activeTabCurrentIndex: 0,
            recentArticles: [article("Two")]
        )

        #expect(DirectoryFingerprint.visible(before) == DirectoryFingerprint.visible(after))
    }

    @Test func unresolvedActiveTabFallsThroughToGlobalRecents() {
        let before = makeInputs(
            recentsScope: .currentTab,
            activeTabID: nil,
            recentArticles: [article("Swift")]
        )
        let after = makeInputs(
            recentsScope: .currentTab,
            activeTabID: nil,
            recentArticles: [article("Swift"), article("Rust")]
        )

        #expect(DirectoryFingerprint.visible(before) != DirectoryFingerprint.visible(after))
    }

    // MARK: - Word-count sensitivity

    @Test func hydratedWordCountsOnlyMatterForNominatedTitles() {
        var counts = ["Swift": 100]
        let inputs = { (titles: [String]) in
            self.makeInputs(
                supplementalSortMode: .articleLength,
                wordCountSensitiveTitles: titles,
                hydratedWordCount: { counts[$0] }
            )
        }

        let before = DirectoryFingerprint.visible(inputs(["Swift"]))
        counts["Swift"] = 250
        let afterTracked = DirectoryFingerprint.visible(inputs(["Swift"]))
        #expect(before != afterTracked)

        let untrackedBefore = DirectoryFingerprint.visible(inputs([]))
        counts["Rust"] = 999
        #expect(untrackedBefore == DirectoryFingerprint.visible(inputs([])))
    }

    @Test func unhydratedWordCountsAreStableUntilTheyArrive() {
        let inputs = makeInputs(
            supplementalSortMode: .articleLength,
            wordCountSensitiveTitles: ["Swift"],
            hydratedWordCount: { _ in nil }
        )

        #expect(DirectoryFingerprint.visible(inputs) == DirectoryFingerprint.visible(inputs))
    }

    // MARK: - Support

    private func makeInputs(
        articleIndexesFingerprint: Int = 0,
        rootSelection: SidebarRootSelection = .recents,
        recentsScope: RecentsScope = .allTabs,
        selectedList: ReadingList? = nil,
        selectedLabel: MacWiki.Label? = nil,
        selectedTag: MacWiki.Tag? = nil,
        localLabelFilter: MacWiki.Label? = nil,
        localTagFilter: MacWiki.Tag? = nil,
        supplementalReadFilter: DirectoryReadFilter = .all,
        supplementalSortMode: DirectorySupplementalSortMode = .recent,
        availableLabelIDs: [UUID] = [],
        availableTagIDs: [UUID] = [],
        savedArticles: [SavedArticle] = [],
        articleStates: [ArticleState] = [],
        highlights: [Highlight] = [],
        activeTabID: UUID? = nil,
        activeTabHistory: [HistoryItem] = [],
        activeTabCurrentIndex: Int? = nil,
        recentArticles: [Article] = [],
        wordCountSensitiveTitles: [String] = [],
        hydratedWordCount: @escaping (String) -> Int? = { _ in nil }
    ) -> DirectoryFingerprint.VisibleInputs {
        DirectoryFingerprint.VisibleInputs(
            articleIndexesFingerprint: articleIndexesFingerprint,
            rootSelection: rootSelection,
            recentsScope: recentsScope,
            selectedList: selectedList,
            selectedLabel: selectedLabel,
            selectedTag: selectedTag,
            localLabelFilter: localLabelFilter,
            localTagFilter: localTagFilter,
            supplementalReadFilter: supplementalReadFilter,
            supplementalSortMode: supplementalSortMode,
            availableLabelIDs: availableLabelIDs,
            availableTagIDs: availableTagIDs,
            savedArticles: savedArticles,
            articleStates: articleStates,
            highlights: highlights,
            activeTabID: activeTabID,
            activeTabHistory: activeTabHistory,
            activeTabCurrentIndex: activeTabCurrentIndex,
            recentArticles: recentArticles,
            wordCountSensitiveTitles: wordCountSensitiveTitles,
            hydratedWordCount: hydratedWordCount
        )
    }

    private func article(_ title: String) -> Article {
        Article(id: title.lowercased(), title: title)
    }

    private func historyItem(title: String) -> HistoryItem {
        HistoryItem(article: article(title))
    }
}
