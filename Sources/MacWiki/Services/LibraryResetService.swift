import SwiftData

/// Deletes the local library as one throwing SwiftData transaction.
///
/// Settings owns the user gesture and status presentation; this service owns the persistence
/// operation. A failed save rolls the context back and propagates the error so Settings can report
/// that the reset did not complete.
@MainActor
enum LibraryResetService {
    static func deleteAll(in modelContext: ModelContext) throws {
        do {
            try deleteAllModels(of: ArticleNote.self, in: modelContext)
            try deleteAllModels(of: Highlight.self, in: modelContext)
            try deleteAllModels(of: ArticleState.self, in: modelContext)
            try deleteAllModels(of: SavedArticle.self, in: modelContext)
            try deleteAllModels(of: ReadingList.self, in: modelContext)
            try deleteAllModels(of: Area.self, in: modelContext)
            try deleteAllModels(of: Label.self, in: modelContext)
            try deleteAllModels(of: Tag.self, in: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private static func deleteAllModels<ModelType: PersistentModel>(
        of type: ModelType.Type,
        in modelContext: ModelContext
    ) throws {
        let models = try modelContext.fetch(FetchDescriptor<ModelType>())
        for model in models {
            modelContext.delete(model)
        }
    }
}
