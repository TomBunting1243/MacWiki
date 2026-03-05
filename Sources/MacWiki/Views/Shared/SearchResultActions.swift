import Foundation
import SwiftData

@MainActor
enum SearchResultActions {
    static func savedArticleTitlesNormalized(from lists: [ReadingList]) -> Set<String> {
        var titles = Set<String>()
        titles.reserveCapacity(lists.reduce(0) { $0 + $1.articles.count })

        for list in lists {
            for article in list.articles {
                titles.insert(ReadStateSync.normalizedTitle(article.title))
            }
        }

        return titles
    }

    @MainActor
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
