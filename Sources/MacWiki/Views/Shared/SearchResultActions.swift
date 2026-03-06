import Foundation
import SwiftData

@MainActor
enum SearchResultActions {
    static func saveToList(
        _ result: WikipediaService.SearchResult,
        list: ReadingList,
        modelContext: ModelContext
    ) {
        let normalizedTitle = ReadStateSync.normalizedTitle(result.title)
        if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalizedTitle }) {
            return
        }

        let saved = SavedArticle(
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL,
            list: list
        )
        saved.isRead = ReadStateSync.resolveReadState(for: result.title, in: modelContext)
        list.articles.append(saved)
        list.updatedAt = Date()
        try? modelContext.save()
        SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
    }
}
