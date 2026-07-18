import Foundation
import SwiftData

struct InspectorArticleKey: Hashable {
    let articleID: String
    let title: String
    let urlString: String

    init(article: Article) {
        articleID = article.id
        title = article.title
        urlString = article.url.absoluteString
    }
}

struct InspectorTagSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int

    init(tag: Tag) {
        id = tag.id
        name = tag.name
        sortOrder = tag.sortOrder
    }
}

struct InspectorLabelSnapshot: Identifiable, Hashable {
    let id: UUID
    let name: String
    let color: LabelColor
    let sortOrder: Int

    init(label: Label) {
        id = label.id
        name = label.name
        color = label.color
        sortOrder = label.sortOrder
    }
}

struct InspectorHighlightSnapshot: Identifiable, Equatable {
    let id: UUID
    let text: String
    let note: String?
    let color: HighlightColor
    let articleTitle: String
    let elementPath: String?
    let startOffset: Int
    let contextBefore: String?
    let contextAfter: String?
    let sectionTitle: String?
    let isStale: Bool
    let isArchived: Bool
    let createdAt: Date
    let updatedAt: Date

    init(highlight: Highlight) {
        id = highlight.id
        text = highlight.text
        note = highlight.note
        color = highlight.color
        articleTitle = highlight.articleTitle
        elementPath = highlight.elementPath
        startOffset = highlight.startOffset
        contextBefore = highlight.contextBefore
        contextAfter = highlight.contextAfter
        sectionTitle = highlight.sectionTitle
        isStale = highlight.isStale
        isArchived = highlight.isArchived
        createdAt = highlight.createdAt
        updatedAt = highlight.updatedAt
    }
}

struct InspectorArticleSnapshot: Equatable {
    let articleKey: InspectorArticleKey?
    let articleStateID: UUID?
    let highlights: [InspectorHighlightSnapshot]
    let tags: [InspectorTagSnapshot]

    static let empty = InspectorArticleSnapshot(
        articleKey: nil,
        articleStateID: nil,
        highlights: [],
        tags: []
    )

    static func empty(for key: InspectorArticleKey?) -> InspectorArticleSnapshot {
        InspectorArticleSnapshot(
            articleKey: key,
            articleStateID: nil,
            highlights: [],
            tags: []
        )
    }

    @MainActor
    static func make(
        article: Article,
        articleState: ArticleState?,
        highlights: [Highlight]
    ) -> InspectorArticleSnapshot {
        var seenTagIDs = Set<UUID>()
        let mergedTags = ((articleState?.tags ?? []) + highlights.flatMap(\.tags))
            .filter { seenTagIDs.insert($0.id).inserted }
            .map(InspectorTagSnapshot.init)
            .sorted {
                if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }

        return InspectorArticleSnapshot(
            articleKey: InspectorArticleKey(article: article),
            articleStateID: articleState?.id,
            highlights: highlights.map(InspectorHighlightSnapshot.init),
            tags: mergedTags
        )
    }
}

struct InspectorArticleSnapshotRefreshKey: Hashable {
    struct HighlightRevision: Hashable {
        let id: UUID
        let text: String
        let note: String?
        let colorRaw: String
        let articleTitle: String
        let elementPath: String?
        let startOffset: Int
        let contextBefore: String?
        let contextAfter: String?
        let sectionTitle: String?
        let isStale: Bool
        let isArchived: Bool
        let createdAt: Date
        let updatedAt: Date
        let tagIDs: [UUID]

        @MainActor
        init(highlight: Highlight) {
            id = highlight.id
            text = highlight.text
            note = highlight.note
            colorRaw = highlight.colorRaw
            articleTitle = highlight.articleTitle
            elementPath = highlight.elementPath
            startOffset = highlight.startOffset
            contextBefore = highlight.contextBefore
            contextAfter = highlight.contextAfter
            sectionTitle = highlight.sectionTitle
            isStale = highlight.isStale
            isArchived = highlight.isArchived
            createdAt = highlight.createdAt
            updatedAt = highlight.updatedAt
            tagIDs = highlight.tags.map(\.id).sorted { $0.uuidString < $1.uuidString }
        }
    }

    struct ArticleStateRevision: Hashable {
        let id: UUID
        let updatedAt: Date
        let tagIDs: [UUID]

        @MainActor
        init(articleState: ArticleState) {
            id = articleState.id
            updatedAt = articleState.updatedAt
            tagIDs = articleState.tags.map(\.id).sorted { $0.uuidString < $1.uuidString }
        }
    }

    struct TagRevision: Hashable {
        let id: UUID
        let name: String
        let sortOrder: Int

        @MainActor
        init(tag: Tag) {
            id = tag.id
            name = tag.name
            sortOrder = tag.sortOrder
        }
    }

    let articleKey: InspectorArticleKey?
    let highlights: [HighlightRevision]
    let articleStates: [ArticleStateRevision]
    let tags: [TagRevision]

    @MainActor
    init(
        articleKey: InspectorArticleKey?,
        highlights: [Highlight],
        articleStates: [ArticleState],
        tags: [Tag]
    ) {
        self.articleKey = articleKey
        self.highlights = highlights.map(HighlightRevision.init)
        self.articleStates = articleStates.map(ArticleStateRevision.init)
        self.tags = tags.map(TagRevision.init)
    }
}

@MainActor
enum InspectorPersistentModelResolver {
    static func highlight(id: UUID, in modelContext: ModelContext) -> Highlight? {
        let descriptor = FetchDescriptor<Highlight>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func tag(id: UUID, in modelContext: ModelContext) -> Tag? {
        let descriptor = FetchDescriptor<Tag>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func label(id: UUID, in modelContext: ModelContext) -> Label? {
        let descriptor = FetchDescriptor<Label>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func articleState(id: UUID, in modelContext: ModelContext) -> ArticleState? {
        let descriptor = FetchDescriptor<ArticleState>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }

    static func savedArticle(id: UUID, in modelContext: ModelContext) -> SavedArticle? {
        let descriptor = FetchDescriptor<SavedArticle>(
            predicate: #Predicate { $0.id == id }
        )
        return try? modelContext.fetch(descriptor).first
    }
}
