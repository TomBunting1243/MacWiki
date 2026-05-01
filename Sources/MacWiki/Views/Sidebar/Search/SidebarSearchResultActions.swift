import SwiftData

@MainActor
extension SearchResultActions {
    static func saveAllToList(
        _ rows: [SidebarSearchRow],
        list: ReadingList,
        modelContext: ModelContext
    ) {
        guard !rows.isEmpty else { return }

        for row in rows {
            if let savedArticle = row.savedArticle {
                ArticleLibraryActions.addSavedArticle(
                    savedArticle,
                    to: list,
                    modelContext: modelContext
                )
            } else {
                ArticleLibraryActions.saveToList(
                    row.article,
                    list: list,
                    modelContext: modelContext
                )
            }
        }
    }
}
