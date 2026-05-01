import Foundation
import SwiftData

@MainActor
enum SearchResultActions {
    static func saveToList(
        _ result: WikipediaService.SearchResult,
        list: ReadingList,
        modelContext: ModelContext
    ) {
        ArticleLibraryActions.saveSearchResultToList(
            result,
            list: list,
            modelContext: modelContext
        )
    }

    static func saveAllToList(
        _ results: [WikipediaService.SearchResult],
        list: ReadingList,
        modelContext: ModelContext
    ) {
        guard !results.isEmpty else { return }

        for result in results {
            ArticleLibraryActions.saveSearchResultToList(
                result,
                list: list,
                modelContext: modelContext
            )
        }
    }
}
