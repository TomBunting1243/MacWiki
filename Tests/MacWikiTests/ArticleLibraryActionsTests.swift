import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct ArticleLibraryActionsTests {
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
