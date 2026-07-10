import Foundation
import SwiftData

@MainActor
enum SavedArticleSummaryBackfill {
    static func enqueueIfNeeded(
        _ savedArticle: SavedArticle,
        modelContext: ModelContext,
        wikipediaService: WikipediaService = .shared
    ) {
        guard requiresBackfill(savedArticle) else { return }

        let title = savedArticle.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }

        Task(priority: .utility) {
            guard let summary = try? await wikipediaService.fetchSummary(title) else { return }

            await MainActor.run {
                var didMutate = false

                if shouldBackfill(savedArticle.articleDescription),
                   let description = normalized(summary.description) {
                    savedArticle.articleDescription = description
                    didMutate = true
                }

                if shouldBackfill(savedArticle.extract),
                   let extract = normalized(summary.extract) {
                    savedArticle.extract = extract
                    didMutate = true
                }

                if savedArticle.thumbnailURLString == nil,
                   let thumbnailURL = summary.thumbnailURL {
                    savedArticle.thumbnailURLString = thumbnailURL.absoluteString
                    didMutate = true
                }

                if didMutate {
                    modelContext.saveReportingFailure(operation: #function)
                }
            }
        }
    }

    private static func requiresBackfill(_ savedArticle: SavedArticle) -> Bool {
        shouldBackfill(savedArticle.articleDescription)
            || shouldBackfill(savedArticle.extract)
            || savedArticle.thumbnailURLString == nil
    }

    private static func shouldBackfill(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
