import Foundation
import SwiftData

@MainActor
enum ReadStateSync {
    static func normalizedTitle(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func urlString(for title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }

    static func fetchArticleState(forURLString urlString: String, in context: ModelContext) -> ArticleState? {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLString == urlString }
        )
        return (try? context.fetch(descriptor))?.first
    }

    static func fetchSavedArticles(for title: String, in context: ModelContext) -> [SavedArticle] {
        let descriptor = FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.title == title }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func resolveReadState(for title: String, in context: ModelContext) -> Bool {
        let urlString = urlString(for: title)
        if let state = fetchArticleState(forURLString: urlString, in: context) {
            return state.isRead
        }
        let savedArticles = fetchSavedArticles(for: title, in: context)
        guard !savedArticles.isEmpty else { return false }
        return savedArticles.allSatisfy { $0.isRead }
    }

    static func resolveReadState(for article: Article, in context: ModelContext) -> Bool {
        resolveReadState(for: article.title, in: context)
    }

    @discardableResult
    static func ensureArticleState(
        for article: Article,
        in context: ModelContext,
        fallbackReadState: Bool? = nil
    ) -> ArticleState {
        let urlString = article.url.absoluteString
        if let state = fetchArticleState(forURLString: urlString, in: context) {
            return state
        }

        let resolvedReadState = fallbackReadState ?? resolveReadState(for: article, in: context)
        let newState = ArticleState(
            articleTitle: article.title,
            articleURL: article.url,
            isRead: resolvedReadState
        )
        context.insert(newState)
        return newState
    }

    static func syncSavedArticles(title: String, isRead: Bool, in context: ModelContext) {
        let savedArticles = fetchSavedArticles(for: title, in: context)
        guard !savedArticles.isEmpty else { return }
        for saved in savedArticles {
            saved.isRead = isRead
        }
    }

    @discardableResult
    static func applyReadState(
        _ isRead: Bool,
        for article: Article,
        in context: ModelContext,
        appState: AppState? = nil
    ) -> ArticleState {
        let state = ensureArticleState(for: article, in: context, fallbackReadState: isRead)
        if state.isRead != isRead {
            state.isRead = isRead
        }

        if isRead {
            let currentProgress = state.readingProgress ?? 0
            if currentProgress < 1 {
                state.readingProgress = 1
            }
        }

        state.updatedAt = Date()
        syncSavedArticles(title: article.title, isRead: isRead, in: context)
        appState?.updateReadState(forTitle: article.title, isRead: isRead)
        try? context.save()
        return state
    }

    @discardableResult
    static func updateReadingProgress(
        _ progress: Double,
        for article: Article,
        in context: ModelContext
    ) -> Double {
        let clamped = min(max(progress, 0), 1)

        let state = ensureArticleState(for: article, in: context)
        let current = state.readingProgress ?? 0

        // Only persist meaningful changes
        if abs(current - clamped) < 0.004 {
            return current
        }

        state.readingProgress = clamped
        state.updatedAt = Date()
        try? context.save()
        return clamped
    }
}
