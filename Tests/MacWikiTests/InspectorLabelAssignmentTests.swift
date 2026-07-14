import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct InspectorLabelAssignmentTests {
    @Test func articleKeyNormalizesTitleVariantsAndTracksArticleIdentity() {
        let first = Article(id: "swift-1", title: "Swift programming language")
        let replacement = Article(id: "swift-2", title: "Swift programming language")
        let key = InspectorLabelArticleKey(article: first)

        #expect(key.normalizedTitle == "swift programming language")
        #expect(Set(key.titleVariants) == [
            "Swift programming language",
            "Swift_programming_language"
        ])
        #expect(key != InspectorLabelArticleKey(article: replacement))
    }

    @Test func loaderCachesOnlyNormalizedMatchesForTheActiveArticle() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "swift", title: "Swift programming language")
        let selectedLabelID = UUID()

        let spaced = SavedArticle(title: "Swift programming language")
        spaced.labelId = selectedLabelID
        let underscored = SavedArticle(title: "Swift_programming_language")
        underscored.labelId = selectedLabelID
        let unrelated = SavedArticle(title: "Swift concurrency")
        unrelated.labelId = UUID()
        modelContext.insert(spaced)
        modelContext.insert(underscored)
        modelContext.insert(unrelated)

        let state = ArticleState(
            articleTitle: article.title,
            articleURL: article.url,
            labelId: UUID()
        )
        modelContext.insert(state)
        try modelContext.save()

        let assignment = InspectorLabelAssignmentLoader.load(
            for: InspectorLabelArticleKey(article: article),
            in: modelContext
        )

        #expect(Set(assignment.savedArticleIDs) == [spaced.id, underscored.id])
        #expect(assignment.articleStateID == state.id)
        #expect(assignment.selectedLabelID == selectedLabelID)
    }

    @Test func selectedLabelFallsBackToArticleStateButRejectsConflictingSavedLabels() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "ada", title: "Ada Lovelace")
        let key = InspectorLabelArticleKey(article: article)
        let fallbackLabelID = UUID()
        let state = ArticleState(
            articleTitle: article.title,
            articleURL: article.url,
            labelId: fallbackLabelID
        )
        let unlabeled = SavedArticle(title: article.title)
        modelContext.insert(state)
        modelContext.insert(unlabeled)
        try modelContext.save()

        let fallback = InspectorLabelAssignmentLoader.load(for: key, in: modelContext)
        #expect(fallback.selectedLabelID == fallbackLabelID)

        unlabeled.labelId = UUID()
        let second = SavedArticle(title: article.title)
        second.labelId = UUID()
        modelContext.insert(second)
        try modelContext.save()
        let conflicting = InspectorLabelAssignmentLoader.load(for: key, in: modelContext)
        #expect(conflicting.selectedLabelID == nil)
    }

    @Test func refreshingBeforeMutationIncludesNewlySavedMatches() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "grace", title: "Grace Hopper")
        let key = InspectorLabelArticleKey(article: article)

        let initial = InspectorLabelAssignmentLoader.load(for: key, in: modelContext)
        #expect(initial.savedArticleIDs.isEmpty)

        let newlySaved = SavedArticle(title: "Grace_Hopper")
        modelContext.insert(newlySaved)
        try modelContext.save()

        let refreshed = InspectorLabelAssignmentLoader.load(for: key, in: modelContext)
        #expect(refreshed.savedArticleIDs == [newlySaved.id])
    }

    @Test func refreshKeyChangesForExternalSavedOrStateLabelMutations() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "grace", title: "Grace Hopper")
        let key = InspectorLabelArticleKey(article: article)
        let list = ReadingList(name: "Inbox")
        let saved = SavedArticle(title: article.title)
        let state = ArticleState(
            articleTitle: article.title,
            articleURL: article.url
        )
        list.articles.append(saved)
        modelContext.insert(list)
        modelContext.insert(state)

        let initial = InspectorLabelAssignmentRefreshKey(
            articleKey: key,
            savedArticles: list.articles,
            articleStates: [state]
        )
        saved.labelId = UUID()
        let savedMutation = InspectorLabelAssignmentRefreshKey(
            articleKey: key,
            savedArticles: list.articles,
            articleStates: [state]
        )
        #expect(savedMutation != initial)

        state.labelId = UUID()
        state.updatedAt = Date(timeIntervalSinceReferenceDate: 123)
        let stateMutation = InspectorLabelAssignmentRefreshKey(
            articleKey: key,
            savedArticles: list.articles,
            articleStates: [state]
        )
        #expect(stateMutation != savedMutation)
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            ReadingList.self,
            SavedArticle.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
