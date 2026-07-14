import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct ArticleLibraryActionsTests {
    @Test func removeAllFromListClearsNormalizedLegacyDuplicatesInOneAction() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let first = SavedArticle(title: "Ada Lovelace", list: list)
        let duplicate = SavedArticle(title: "Ada_Lovelace", list: list)
        let unrelated = SavedArticle(title: "Grace Hopper", list: list)
        list.articles = [first, duplicate, unrelated]
        modelContext.insert(list)

        let removedCount = ArticleLibraryActions.removeAllFromList(
            withTitle: "Ada Lovelace",
            list: list,
            modelContext: modelContext
        )

        #expect(removedCount == 2)
        #expect(list.articles.map(\.title) == ["Grace Hopper"])
    }

    @Test func saveSearchResultToListDeduplicatesAndResolvesReadState() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let state = ArticleState(
            articleTitle: "Swift",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Swift"))!,
            isRead: true
        )
        modelContext.insert(list)
        modelContext.insert(state)

        let result = WikipediaService.SearchResult(
            id: "swift",
            title: "Swift",
            description: "A language",
            thumbnailURL: URL(string: "https://example.com/swift.png")
        )

        ArticleLibraryActions.saveSearchResultToList(result, list: list, modelContext: modelContext)
        ArticleLibraryActions.saveSearchResultToList(result, list: list, modelContext: modelContext)

        #expect(list.articles.count == 1)
        #expect(list.articles.first?.title == "Swift")
        #expect(list.articles.first?.isRead == true)
    }

    @Test func saveAllSearchResultsToListDeduplicatesAndResolvesReadState() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let state = ArticleState(
            articleTitle: "Swift programming language",
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Swift programming language"))!,
            isRead: true
        )
        let existing = SavedArticle(title: "Ada_Lovelace", list: list)
        list.articles = [existing]

        modelContext.insert(list)
        modelContext.insert(state)
        modelContext.insert(existing)

        let results = [
            WikipediaService.SearchResult(
                id: "ada",
                title: "Ada Lovelace",
                description: nil,
                thumbnailURL: nil
            ),
            WikipediaService.SearchResult(
                id: "swift",
                title: "Swift programming language",
                description: "A language",
                thumbnailURL: URL(string: "https://example.com/swift.png")
            ),
            WikipediaService.SearchResult(
                id: "swift-dupe",
                title: "Swift_programming_language",
                description: "Duplicate title spelling",
                thumbnailURL: nil
            )
        ]

        SearchResultActions.saveAllToList(results, list: list, modelContext: modelContext)

        #expect(list.articles.map { ReadStateSync.normalizedTitle($0.title) }.sorted() == [
            "ada lovelace",
            "swift programming language"
        ])
        #expect(list.articles.first { $0.title == "Swift programming language" }?.isRead == true)
    }

    @Test func saveVisibleSearchRowsPreservesHydratedAndSavedMetadata() throws {
        let modelContext = try makeInMemoryModelContext()
        let source = ReadingList(name: "Source")
        let target = ReadingList(name: "Target")
        let label = Label(name: "Research", color: .blue)
        let existing = SavedArticle(
            title: "Existing Article",
            description: "Saved description",
            extract: "Saved extract",
            list: source,
            wordCount: 900
        )
        existing.isRead = true
        existing.labelId = label.id
        source.articles = [existing]

        modelContext.insert(source)
        modelContext.insert(target)
        modelContext.insert(label)
        modelContext.insert(existing)

        let snapshot = SidebarSearchSnapshotBuilder.build(
            sourceResults: [
                WikipediaService.SearchResult(
                    id: "hydrated",
                    title: "Hydrated Article",
                    description: "Search description",
                    thumbnailURL: nil
                ),
                WikipediaService.SearchResult(
                    id: "existing",
                    title: "Existing Article",
                    description: nil,
                    thumbnailURL: nil
                )
            ],
            sourceKind: .query,
            readFilter: .all,
            sortMode: .relevance,
            articleIndexes: DirectoryArticleIndexes(
                articleStates: [],
                highlights: [],
                savedArticles: [existing]
            ),
            labels: [label],
            currentArticleTitleNormalized: nil,
            metadataSnapshot: { title in
                guard title == "Hydrated Article" else { return nil }
                return ArticleMetadataHydrationSnapshot(
                    description: "Hydrated description",
                    extract: "Hydrated extract",
                    thumbnailURL: URL(string: "https://example.com/hydrated.png"),
                    wordCount: 1_300
                )
            }
        )

        SearchResultActions.saveAllToList(snapshot.rows, list: target, modelContext: modelContext)

        let copiedExisting = target.articles.first { $0.title == "Existing Article" }
        let hydrated = target.articles.first { $0.title == "Hydrated Article" }

        #expect(target.articles.count == 2)
        #expect(copiedExisting?.isRead == true)
        #expect(copiedExisting?.labelId == label.id)
        #expect(copiedExisting?.wordCount == 900)
        #expect(hydrated?.articleDescription == "Hydrated description")
        #expect(hydrated?.extract == "Hydrated extract")
        #expect(hydrated?.thumbnailURL == URL(string: "https://example.com/hydrated.png"))
        #expect(hydrated?.wordCount == 1_300)
    }

    @Test func moveArticleCopiesFieldsIntoTargetAndRemovesSource() throws {
        let modelContext = try makeInMemoryModelContext()
        let source = ReadingList(name: "Source")
        let target = ReadingList(name: "Target")
        let article = SavedArticle(
            title: "Alan Turing",
            description: "Mathematician",
            extract: "Pioneer",
            thumbnailURL: URL(string: "https://example.com/turing.png"),
            list: source,
            wordCount: 900
        )
        article.isRead = true
        article.labelId = UUID()
        source.articles = [article]

        modelContext.insert(source)
        modelContext.insert(target)
        modelContext.insert(article)

        ArticleLibraryActions.moveArticle(
            article,
            from: source,
            to: target,
            modelContext: modelContext
        )

        #expect(source.articles.isEmpty)
        #expect(target.articles.count == 1)
        #expect(target.articles.first?.title == "Alan Turing")
        #expect(target.articles.first?.isRead == true)
        #expect(target.articles.first?.labelId == article.labelId)
        #expect(target.articles.first?.wordCount == 900)
    }

    @Test func applyLabelAndAddTagUpdateSavedArticlesAndArticleState() throws {
        let modelContext = try makeInMemoryModelContext()
        let label = Label(name: "Important", color: .red)
        let tag = Tag(name: "Pinned")
        let article = SavedArticle(title: "Grace Hopper")
        let state = ArticleState(
            articleTitle: article.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "Grace_Hopper"))!
        )

        modelContext.insert(label)
        modelContext.insert(tag)
        modelContext.insert(article)
        modelContext.insert(state)

        ArticleLibraryActions.applyLabel(label.id, to: [article], modelContext: modelContext)
        ArticleLibraryActions.addTag(tag, to: [article], modelContext: modelContext)

        let refreshedState = ArticleLibraryActions.articleState(for: article.title, modelContext: modelContext)

        #expect(article.labelId == label.id)
        #expect(refreshedState?.labelId == label.id)
        #expect(refreshedState?.tags.map(\.name) == ["Pinned"])
    }

    @Test func moveDroppedArticlePreservesMetadataAndExistingArticleState() throws {
        let modelContext = try makeInMemoryModelContext()
        let source = ReadingList(name: "Source")
        let target = ReadingList(name: "Target")
        let tag = Tag(name: "Pinned")
        let article = SavedArticle(
            title: "Ada Lovelace",
            description: "Mathematician",
            extract: "Analytical Engine",
            thumbnailURL: URL(string: "https://example.com/ada.png"),
            list: source,
            wordCount: 1_200
        )
        article.isRead = true
        let labelID = UUID()
        article.labelId = labelID

        let state = ArticleState(
            articleTitle: article.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: article.title))!
        )
        state.tags = [tag]

        source.articles = [article]

        modelContext.insert(source)
        modelContext.insert(target)
        modelContext.insert(tag)
        modelContext.insert(article)
        modelContext.insert(state)

        let payload = SavedArticleDragPayload(savedArticleID: article.id, sourceListID: source.id)
        let moved = ArticleLibraryActions.moveDroppedArticle(payload, to: target, modelContext: modelContext)

        #expect(moved)
        #expect(source.articles.isEmpty)
        #expect(target.articles.count == 1)
        #expect(target.articles.first?.title == "Ada Lovelace")
        #expect(target.articles.first?.articleDescription == "Mathematician")
        #expect(target.articles.first?.extract == "Analytical Engine")
        #expect(target.articles.first?.thumbnailURL == URL(string: "https://example.com/ada.png"))
        #expect(target.articles.first?.isRead == true)
        #expect(target.articles.first?.labelId == labelID)
        #expect(target.articles.first?.wordCount == 1_200)
        #expect(ArticleLibraryActions.savedArticle(for: article.id, modelContext: modelContext) == nil)
        #expect(ArticleLibraryActions.articleState(for: article.title, modelContext: modelContext)?.tags.map(\.name) == ["Pinned"])
    }

    @Test func applyDroppedArticleCreatesOrUpdatesArticleStateLabel() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let label = Label(name: "Important", color: .red)
        let article = SavedArticle(title: "Grace Hopper", list: list)

        list.articles = [article]

        modelContext.insert(list)
        modelContext.insert(label)
        modelContext.insert(article)

        let payload = SavedArticleDragPayload(savedArticleID: article.id, sourceListID: list.id)
        let applied = ArticleLibraryActions.applyDroppedArticle(payload, labelId: label.id, modelContext: modelContext)

        let refreshedState = ArticleLibraryActions.articleState(for: article.title, modelContext: modelContext)

        #expect(applied)
        #expect(article.labelId == label.id)
        #expect(refreshedState?.labelId == label.id)
    }

    @Test func addDroppedArticleDeduplicatesExistingTag() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let tag = Tag(name: "Pinned")
        let article = SavedArticle(title: "Margaret Hamilton", list: list)
        let state = ArticleState(
            articleTitle: article.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: article.title))!
        )
        state.tags = [tag]

        list.articles = [article]

        modelContext.insert(list)
        modelContext.insert(tag)
        modelContext.insert(article)
        modelContext.insert(state)

        let payload = SavedArticleDragPayload(savedArticleID: article.id, sourceListID: list.id)
        let added = ArticleLibraryActions.addDroppedArticle(payload, tag: tag, modelContext: modelContext)

        #expect(!added)
        #expect(ArticleLibraryActions.articleState(for: article.title, modelContext: modelContext)?.tags.count == 1)
    }

    @Test func droppedArticleHelpersNoOpForExistingDestinations() throws {
        let modelContext = try makeInMemoryModelContext()
        let source = ReadingList(name: "Source")
        let label = Label(name: "Pinned", color: .blue)
        let tag = Tag(name: "Reference")
        let article = SavedArticle(title: "Barbara Liskov", list: source)
        article.labelId = label.id

        let state = ArticleState(
            articleTitle: article.title,
            articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: article.title))!
        )
        state.tags = [tag]

        source.articles = [article]

        modelContext.insert(source)
        modelContext.insert(label)
        modelContext.insert(tag)
        modelContext.insert(article)
        modelContext.insert(state)

        let payload = SavedArticleDragPayload(savedArticleID: article.id, sourceListID: source.id)

        let moved = ArticleLibraryActions.moveDroppedArticle(payload, to: source, modelContext: modelContext)
        let relabeled = ArticleLibraryActions.applyDroppedArticle(payload, labelId: label.id, modelContext: modelContext)
        let retagged = ArticleLibraryActions.addDroppedArticle(payload, tag: tag, modelContext: modelContext)

        #expect(!moved)
        #expect(!relabeled)
        #expect(!retagged)
        #expect(source.articles.count == 1)
        #expect(source.articles.first?.labelId == label.id)
        #expect(ArticleLibraryActions.articleState(for: article.title, modelContext: modelContext)?.tags.count == 1)
    }

    @Test func moveDroppedRecentArticleCreatesSavedArticleInTargetList() throws {
        let modelContext = try makeInMemoryModelContext()
        let target = ReadingList(name: "Inbox")
        modelContext.insert(target)

        let payload = SavedArticleDragPayload(
            title: "Katherine Johnson",
            articleDescription: "NASA mathematician",
            extract: "Orbital mechanics",
            thumbnailURL: URL(string: "https://example.com/katherine.png"),
            isRead: true,
            wordCount: 1_600
        )

        let moved = ArticleLibraryActions.moveDroppedArticle(payload, to: target, modelContext: modelContext)

        #expect(moved)
        #expect(target.articles.count == 1)
        #expect(target.articles.first?.title == "Katherine Johnson")
        #expect(target.articles.first?.articleDescription == "NASA mathematician")
        #expect(target.articles.first?.extract == "Orbital mechanics")
        #expect(target.articles.first?.thumbnailURL == URL(string: "https://example.com/katherine.png"))
        #expect(target.articles.first?.isRead == true)
        #expect(target.articles.first?.wordCount == 1_600)
    }

    @Test func applyDroppedRecentArticleCreatesSavedArticleAndStateLabel() throws {
        let modelContext = try makeInMemoryModelContext()
        let inbox = ReadingList(name: "Inbox")
        let label = Label(name: "Important", color: .red)
        modelContext.insert(inbox)
        modelContext.insert(label)

        let payload = SavedArticleDragPayload(
            title: "Dorothy Vaughan",
            articleDescription: "Computer programmer",
            isRead: false
        )

        let applied = ArticleLibraryActions.applyDroppedArticle(
            payload,
            labelId: label.id,
            defaultList: inbox,
            modelContext: modelContext
        )

        #expect(applied)
        #expect(inbox.articles.count == 1)
        #expect(inbox.articles.first?.title == "Dorothy Vaughan")
        #expect(inbox.articles.first?.labelId == label.id)
        #expect(ArticleLibraryActions.articleState(for: "Dorothy Vaughan", modelContext: modelContext)?.labelId == label.id)
    }

    @Test func addDroppedRecentArticleCreatesArticleStateTagWithoutDuplicateSavedArticle() throws {
        let modelContext = try makeInMemoryModelContext()
        let tag = Tag(name: "Research")
        modelContext.insert(tag)

        let payload = SavedArticleDragPayload(title: "Mary Jackson")

        let added = ArticleLibraryActions.addDroppedArticle(payload, tag: tag, modelContext: modelContext)
        let addedAgain = ArticleLibraryActions.addDroppedArticle(payload, tag: tag, modelContext: modelContext)

        #expect(added)
        #expect(!addedAgain)
        #expect(ArticleLibraryActions.articleState(for: "Mary Jackson", modelContext: modelContext)?.tags.map(\.name) == ["Research"])
        #expect(ArticleLibraryActions.savedArticle(forTitle: "Mary Jackson", modelContext: modelContext) == nil)
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            Label.self,
            ReadingList.self,
            SavedArticle.self,
            Highlight.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
