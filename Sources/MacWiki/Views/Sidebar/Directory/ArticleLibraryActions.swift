import Foundation
import SwiftData

@MainActor
enum ArticleLibraryActions {
    static func batchMarkTitles(
        _ titles: some Sequence<String>,
        asRead: Bool,
        modelContext: ModelContext,
        appState: AppState,
        touchedList: ReadingList? = nil
    ) {
        for title in Set(titles) {
            let article = Article(id: title, title: title, isRead: asRead)
            _ = ReadStateSync.applyReadState(asRead, for: article, in: modelContext, appState: appState)
        }

        touchedList?.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    static func toggleReadStatus(
        for savedArticle: SavedArticle,
        effectiveReadState: Bool,
        modelContext: ModelContext,
        appState: AppState
    ) {
        let newValue = !effectiveReadState
        let resolvedArticle = Article(
            id: savedArticle.title,
            title: savedArticle.title,
            description: savedArticle.articleDescription,
            extract: savedArticle.extract,
            thumbnailURL: savedArticle.thumbnailURL,
            isRead: newValue,
            wordCount: savedArticle.wordCount
        )
        _ = ReadStateSync.applyReadState(newValue, for: resolvedArticle, in: modelContext, appState: appState)
    }

    static func applyLabel(
        _ labelId: UUID?,
        to savedArticles: [SavedArticle],
        modelContext: ModelContext
    ) {
        guard !savedArticles.isEmpty else { return }

        for article in savedArticles {
            article.labelId = labelId

            if let labelId,
               let state = ensureArticleState(for: article.title, modelContext: modelContext) {
                state.labelId = labelId
                state.updatedAt = Date()
            } else if let state = articleState(for: article.title, modelContext: modelContext) {
                state.labelId = labelId
                state.updatedAt = Date()
            }

            article.readingList?.updatedAt = Date()
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    @discardableResult
    static func moveDroppedArticle(
        _ payload: SavedArticleDragPayload,
        to targetList: ReadingList,
        modelContext: ModelContext
    ) -> Bool {
        guard payload.sourceListID != targetList.id else { return false }
        if let savedArticle = resolvedSavedArticle(
            for: payload,
            modelContext: modelContext,
            createsIfNeeded: false
        ) {
            guard savedArticle.readingList?.id != targetList.id else { return false }
            guard !containsArticle(withTitle: savedArticle.title, in: targetList) else { return false }

            return moveArticle(
                savedArticle,
                from: savedArticle.readingList,
                to: targetList,
                modelContext: modelContext
            )
        }

        guard let title = payload.title else { return false }
        guard !containsArticle(withTitle: title, in: targetList) else { return false }
        return resolvedSavedArticle(
            for: payload,
            modelContext: modelContext,
            defaultList: targetList
        ) != nil
    }

    @discardableResult
    static func applyDroppedArticle(
        _ payload: SavedArticleDragPayload,
        labelId: UUID,
        defaultList: ReadingList? = nil,
        modelContext: ModelContext
    ) -> Bool {
        guard let savedArticle = resolvedSavedArticle(
            for: payload,
            modelContext: modelContext,
            defaultList: defaultList
        ) else {
            return false
        }
        guard savedArticle.labelId != labelId else { return false }

        applyLabel(labelId, to: [savedArticle], modelContext: modelContext)
        return true
    }

    @discardableResult
    static func addDroppedArticle(
        _ payload: SavedArticleDragPayload,
        tag: Tag,
        modelContext: ModelContext
    ) -> Bool {
        if let savedArticle = resolvedSavedArticle(
            for: payload,
            modelContext: modelContext,
            createsIfNeeded: false
        ) {
            if articleState(for: savedArticle.title, modelContext: modelContext)?.tags.contains(where: { $0.id == tag.id }) == true {
                return false
            }

            addTag(tag, to: [savedArticle], modelContext: modelContext)
            return true
        }

        guard let title = payload.title,
              let state = ensureArticleState(for: title, modelContext: modelContext) else {
            return false
        }

        if state.tags.contains(where: { $0.id == tag.id }) {
            return false
        }

        state.tags.append(tag)
        state.updatedAt = Date()
        return modelContext.saveReportingFailure(operation: #function)
    }

    static func addTag(
        _ tag: Tag,
        to savedArticles: [SavedArticle],
        modelContext: ModelContext
    ) {
        guard !savedArticles.isEmpty else { return }

        for article in savedArticles {
            guard let state = ensureArticleState(for: article.title, modelContext: modelContext) else { continue }
            if !state.tags.contains(where: { $0.id == tag.id }) {
                state.tags.append(tag)
            }
            state.updatedAt = Date()
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    static func removeTag(
        _ tag: Tag,
        from savedArticles: [SavedArticle],
        modelContext: ModelContext
    ) {
        guard !savedArticles.isEmpty else { return }

        for article in savedArticles {
            guard let state = articleState(for: article.title, modelContext: modelContext) else { continue }
            state.tags.removeAll { $0.id == tag.id }
            state.updatedAt = Date()
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    static func toggleTag(
        _ tag: Tag,
        for article: Article,
        modelContext: ModelContext
    ) {
        if let state = articleState(for: article.title, modelContext: modelContext) {
            if let index = state.tags.firstIndex(where: { $0.id == tag.id }) {
                state.tags.remove(at: index)
            } else {
                state.tags.append(tag)
            }
            state.updatedAt = Date()
        } else {
            let newState = ArticleState(articleTitle: article.title, articleURL: article.url)
            newState.tags.append(tag)
            modelContext.insert(newState)
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    static func saveToList(
        _ article: Article,
        list: ReadingList,
        modelContext: ModelContext
    ) {
        guard !containsArticle(withTitle: article.title, in: list) else { return }

        let saved = SavedArticle(
            title: article.title,
            description: article.description,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            list: list,
            wordCount: article.wordCount
        )
        saved.isRead = ReadStateSync.resolveReadState(for: article, in: modelContext)
        list.articles.append(saved)
        list.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
    }

    static func saveSearchResultToList(
        _ result: WikipediaService.SearchResult,
        list: ReadingList,
        modelContext: ModelContext
    ) {
        let article = Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
        saveToList(article, list: list, modelContext: modelContext)
    }

    static func addSavedArticles(
        _ savedArticles: [SavedArticle],
        to targetList: ReadingList,
        modelContext: ModelContext
    ) {
        guard !savedArticles.isEmpty else { return }

        var didAdd = false
        for article in savedArticles {
            if article.readingList?.id == targetList.id { continue }
            guard !containsArticle(withTitle: article.title, in: targetList) else { continue }

            let copied = SavedArticle(
                title: article.title,
                description: article.articleDescription,
                extract: article.extract,
                thumbnailURL: article.thumbnailURL,
                list: targetList,
                wordCount: article.wordCount
            )
            copied.isRead = article.isRead
            copied.labelId = article.labelId
            targetList.articles.append(copied)
            didAdd = true
        }

        guard didAdd else { return }
        targetList.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    static func addSavedArticle(
        _ savedArticle: SavedArticle,
        to targetList: ReadingList,
        modelContext: ModelContext
    ) {
        if let sourceList = savedArticle.readingList {
            guard sourceList.id != targetList.id else { return }
            addSavedArticles([savedArticle], to: targetList, modelContext: modelContext)
            return
        }

        savedArticle.readingList = targetList
        if !targetList.articles.contains(where: { $0.id == savedArticle.id }) {
            targetList.articles.append(savedArticle)
        }
        targetList.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    static func removeFromList(
        _ article: SavedArticle,
        list: ReadingList,
        modelContext: ModelContext
    ) {
        guard let index = list.articles.firstIndex(where: { $0.id == article.id }) else { return }
        list.articles.remove(at: index)
        list.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
    }

    /// Removes every saved representation of a title in one transaction.
    ///
    /// Older stores can contain normalized-title duplicates from releases that
    /// predate the current save-time guard. Membership toggles must clear the
    /// entire logical membership instead of exposing a still-saved duplicate.
    @discardableResult
    static func removeAllFromList(
        withTitle title: String,
        list: ReadingList,
        modelContext: ModelContext
    ) -> Int {
        let normalizedTitle = ReadStateSync.normalizedTitle(title)
        let originalCount = list.articles.count
        list.articles.removeAll {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }
        let removedCount = originalCount - list.articles.count
        guard removedCount > 0 else { return 0 }

        list.updatedAt = Date()
        modelContext.saveReportingFailure(operation: #function)
        return removedCount
    }

    static func removeSavedArticle(
        _ article: SavedArticle,
        modelContext: ModelContext
    ) {
        if let list = article.readingList {
            removeFromList(article, list: list, modelContext: modelContext)
        } else {
            modelContext.delete(article)
            modelContext.saveReportingFailure(operation: #function)
        }
    }

    static func deleteSavedArticles(
        _ savedArticles: [SavedArticle],
        modelContext: ModelContext
    ) {
        guard !savedArticles.isEmpty else { return }

        for article in savedArticles {
            if let list = article.readingList {
                list.articles.removeAll { $0.id == article.id }
                list.updatedAt = Date()
            } else {
                modelContext.delete(article)
            }
        }

        modelContext.saveReportingFailure(operation: #function)
    }

    @discardableResult
    static func moveArticle(
        _ article: SavedArticle,
        from source: ReadingList?,
        to target: ReadingList,
        modelContext: ModelContext
    ) -> Bool {
        guard source?.id != target.id else { return false }
        guard !containsArticle(withTitle: article.title, in: target) else { return false }

        let movedArticle = SavedArticle(
            title: article.title,
            description: article.articleDescription,
            extract: article.extract,
            thumbnailURL: article.thumbnailURL,
            list: target,
            wordCount: article.wordCount
        )
        movedArticle.isRead = article.isRead
        movedArticle.labelId = article.labelId
        target.articles.append(movedArticle)
        target.updatedAt = Date()

        if let source {
            source.articles.removeAll { $0.id == article.id }
            source.updatedAt = Date()
        }

        modelContext.delete(article)

        return modelContext.saveReportingFailure(operation: #function)
    }

    static func containsArticle(withTitle title: String, in list: ReadingList) -> Bool {
        let normalizedTitle = ReadStateSync.normalizedTitle(title)
        return list.articles.contains { ReadStateSync.normalizedTitle($0.title) == normalizedTitle }
    }

    static func savedArticle(
        for id: UUID,
        modelContext: ModelContext
    ) -> SavedArticle? {
        let descriptor = FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func savedArticle(
        forTitle title: String,
        modelContext: ModelContext
    ) -> SavedArticle? {
        let normalizedTitle = ReadStateSync.normalizedTitle(title)
        let descriptor = FetchDescriptor<SavedArticle>()
        let savedArticles = (try? modelContext.fetch(descriptor)) ?? []
        return savedArticles.first {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }
    }

    @discardableResult
    static func resolvedSavedArticle(
        for payload: SavedArticleDragPayload,
        modelContext: ModelContext,
        defaultList: ReadingList? = nil,
        createsIfNeeded: Bool = true
    ) -> SavedArticle? {
        if let id = payload.savedArticleID,
           let existing = savedArticle(for: id, modelContext: modelContext) {
            return existing
        }

        if let title = payload.title,
           let existing = savedArticle(forTitle: title, modelContext: modelContext) {
            return existing
        }

        guard createsIfNeeded else { return nil }
        guard let title = payload.title else { return nil }

        let saved = SavedArticle(
            title: title,
            description: payload.articleDescription,
            extract: payload.extract,
            thumbnailURL: payload.thumbnailURL,
            list: defaultList,
            wordCount: payload.wordCount
        )
        if let isRead = payload.isRead {
            saved.isRead = isRead
        }

        if let defaultList {
            defaultList.articles.append(saved)
            defaultList.updatedAt = Date()
        } else {
            modelContext.insert(saved)
        }

        guard modelContext.saveReportingFailure(operation: #function) else { return nil }
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
        return saved
    }

    static func articleState(
        for title: String,
        modelContext: ModelContext
    ) -> ArticleState? {
        let urlString = ReadStateSync.urlString(for: title)
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.articleURLString == urlString }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func ensureArticleState(
        for title: String,
        modelContext: ModelContext
    ) -> ArticleState? {
        if let existingState = articleState(for: title, modelContext: modelContext) {
            return existingState
        }

        guard let url = URL(string: ReadStateSync.urlString(for: title)) else { return nil }
        let newState = ArticleState(articleTitle: title, articleURL: url)
        modelContext.insert(newState)
        return newState
    }
}
