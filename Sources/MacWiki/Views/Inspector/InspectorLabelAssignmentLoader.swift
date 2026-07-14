import Foundation
import SwiftData

struct InspectorLabelArticleKey: Hashable {
    let articleID: String
    let title: String
    let normalizedTitle: String
    let urlString: String

    @MainActor
    init(article: Article) {
        articleID = article.id
        title = article.title
        normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        urlString = article.url.absoluteString
    }

    var titleVariants: [String] {
        Array(Set([
            title,
            title.replacingOccurrences(of: "_", with: " "),
            title.replacingOccurrences(of: " ", with: "_")
        ])).sorted()
    }
}

struct InspectorLabelAssignment {
    let articleKey: InspectorLabelArticleKey
    let savedArticles: [SavedArticle]
    let articleState: ArticleState?

    var selectedLabelID: UUID? {
        let savedLabelIDs = Set(savedArticles.compactMap(\.labelId))
        guard !savedArticles.isEmpty else { return articleState?.labelId }
        if savedLabelIDs.count == 1 { return savedLabelIDs.first }
        return savedLabelIDs.isEmpty ? articleState?.labelId : nil
    }
}

struct InspectorLabelAssignmentRefreshKey: Hashable {
    private struct SavedAssignment: Hashable {
        let id: UUID
        let labelID: UUID?
    }

    private struct StateAssignment: Hashable {
        let id: UUID
        let labelID: UUID?
    }

    let articleKey: InspectorLabelArticleKey
    private let savedAssignments: [SavedAssignment]
    private let stateAssignments: [StateAssignment]

    @MainActor
    init(
        articleKey: InspectorLabelArticleKey,
        savedArticles: [SavedArticle],
        articleStates: [ArticleState]
    ) {
        self.articleKey = articleKey

        var seenSavedIDs = Set<UUID>()
        savedAssignments = savedArticles
            .filter {
                ReadStateSync.normalizedTitle($0.title)
                    == articleKey.normalizedTitle
            }
            .filter { seenSavedIDs.insert($0.id).inserted }
            .map { SavedAssignment(id: $0.id, labelID: $0.labelId) }
            .sorted { $0.id.uuidString < $1.id.uuidString }

        stateAssignments = articleStates
            .map {
                StateAssignment(
                    id: $0.id,
                    labelID: $0.labelId
                )
            }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

@MainActor
enum InspectorLabelAssignmentLoader {
    static func load(
        for articleKey: InspectorLabelArticleKey,
        in modelContext: ModelContext
    ) -> InspectorLabelAssignment {
        var matches: [SavedArticle] = []
        var seenIDs = Set<UUID>()

        for title in articleKey.titleVariants {
            let descriptor = FetchDescriptor<SavedArticle>(
                predicate: #Predicate { $0.title == title }
            )
            let rows = (try? modelContext.fetch(descriptor)) ?? []
            for row in rows where seenIDs.insert(row.id).inserted {
                guard ReadStateSync.normalizedTitle(row.title) == articleKey.normalizedTitle else { continue }
                matches.append(row)
            }
        }

        let state = ReadStateSync.fetchArticleState(
            forURLString: articleKey.urlString,
            in: modelContext
        )
        return InspectorLabelAssignment(
            articleKey: articleKey,
            savedArticles: matches,
            articleState: state
        )
    }
}
