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
}
