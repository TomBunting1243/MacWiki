import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
@Suite
struct InspectorArticleSnapshotTests {
    @Test func snapshotSurvivesExternalPersistentModelDeletion() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "snapshot-article", title: "Snapshot Article")
        let tag = Tag(name: "Research")
        let state = ArticleState(articleTitle: article.title, articleURL: article.url)
        let highlight = Highlight(
            text: "Stable value projection",
            articleTitle: article.title,
            startOffset: 0,
            length: 23,
            color: .blue
        )
        state.tags = [tag]
        highlight.tags = [tag]
        modelContext.insert(tag)
        modelContext.insert(state)
        modelContext.insert(highlight)
        try modelContext.save()

        let highlightID = highlight.id
        let tagID = tag.id
        let snapshot = InspectorArticleSnapshot.make(
            article: article,
            articleState: state,
            highlights: [highlight]
        )

        modelContext.delete(highlight)
        modelContext.delete(state)
        modelContext.delete(tag)
        try modelContext.save()

        #expect(snapshot.articleKey == InspectorArticleKey(article: article))
        #expect(snapshot.highlights.map(\.text) == ["Stable value projection"])
        #expect(snapshot.highlights.map(\.color) == [.blue])
        #expect(snapshot.tags.map(\.name) == ["Research"])
        #expect(InspectorPersistentModelResolver.highlight(id: highlightID, in: modelContext) == nil)
        #expect(InspectorPersistentModelResolver.tag(id: tagID, in: modelContext) == nil)
    }

    @Test func sameTitleDifferentArticleIdentityInvalidatesSnapshotWork() {
        let first = Article(id: "article-a", title: "Shared Title")
        let second = Article(id: "article-b", title: "Shared Title")

        #expect(InspectorArticleKey(article: first) != InspectorArticleKey(article: second))
    }

    @Test func refreshKeyTracksStaleStateEvenWithoutTimestampMutation() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "stale-refresh", title: "Stale Refresh")
        let highlight = Highlight(
            text: "Refresh stale state",
            articleTitle: article.title,
            startOffset: 0,
            length: 19
        )
        modelContext.insert(highlight)
        try modelContext.save()

        let initial = InspectorArticleSnapshotRefreshKey(
            articleKey: InspectorArticleKey(article: article),
            highlights: [highlight],
            articleStates: [],
            tags: []
        )
        let unchangedTimestamp = highlight.updatedAt
        highlight.isStale = true
        let stale = InspectorArticleSnapshotRefreshKey(
            articleKey: InspectorArticleKey(article: article),
            highlights: [highlight],
            articleStates: [],
            tags: []
        )

        #expect(highlight.updatedAt == unchangedTimestamp)
        #expect(initial != stale)
    }

    @Test func tagDetailTargetSurvivesExternalDeletion() throws {
        let modelContext = try makeInMemoryModelContext()
        let tag = Tag(name: "Ephemeral")
        modelContext.insert(tag)
        try modelContext.save()
        let target = TagDetailSheetTarget(tag: tag)

        modelContext.delete(tag)
        try modelContext.save()

        #expect(target.name == "Ephemeral")
        #expect(InspectorPersistentModelResolver.tag(id: target.id, in: modelContext) == nil)
    }

    @Test func deletedLabelCannotBeResolvedForAssignment() throws {
        let modelContext = try makeInMemoryModelContext()
        let label = Label(name: "Temporary")
        modelContext.insert(label)
        try modelContext.save()
        let labelID = label.id

        modelContext.delete(label)
        try modelContext.save()

        #expect(InspectorPersistentModelResolver.label(id: labelID, in: modelContext) == nil)
    }

    @Test func inspectorStoresValueSnapshotsInsteadOfPersistentModels() throws {
        let panel = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let tags = try source("Sources/MacWiki/Views/Inspector/InspectorTagStatusBox.swift")
        let rows = try source("Sources/MacWiki/Views/Components/HighlightRowView.swift")
        let tagDetail = try source("Sources/MacWiki/Views/Components/TagDetailSheet.swift")

        #expect(panel.contains("@State private var articleSnapshot = InspectorArticleSnapshot.empty"))
        #expect(!panel.contains("@State private var currentArticleState: ArticleState?"))
        #expect(!panel.contains("@State private var cachedCurrentArticleHighlights: [Highlight]"))
        #expect(!panel.contains("@State private var cachedCurrentArticleTags: [Tag]"))
        #expect(tags.contains("@State private var editingTagID: UUID?"))
        #expect(!tags.contains("@State private var articleState: ArticleState?"))
        #expect(!tags.contains("@State private var editingTag: Tag?"))
        #expect(rows.contains("let highlight: InspectorHighlightSnapshot"))
        #expect(rows.contains("InspectorPersistentModelResolver.highlight"))
        #expect(tagDetail.contains("private let target: TagDetailSheetTarget?"))
        #expect(!tagDetail.contains("var tagToEdit: Tag?"))
    }

    @Test func inspectorAppearanceReadsExistingStateWithoutPersistenceSideEffects() throws {
        let panel = try source("Sources/MacWiki/Views/Inspector/InspectorPanel.swift")
        let labels = try source("Sources/MacWiki/Views/Inspector/InspectorLabelSection.swift")
        let tags = try source("Sources/MacWiki/Views/Inspector/InspectorTagStatusBox.swift")

        #expect(panel.contains("let state = currentArticleStates.first"))
        #expect(!panel.contains("loadOrCreateArticleState"))
        #expect(!panel.contains("ReadStateSync.syncSavedArticles"))
        #expect(!panel.contains("ReadStateSync.resolveReadState"))
        #expect(!panel.contains("modelContext.insert(newState)"))
        #expect(!panel.contains("modelContext.saveReportingFailure"))
        #expect(!panel.contains("appState.updateReadState"))

        // Explicit organization edits retain their lazy mutation boundary.
        #expect(labels.contains("ReadStateSync.ensureArticleState(for: article, in: modelContext)"))
        #expect(tags.contains("ReadStateSync.ensureArticleState(for: article, in: modelContext)"))
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Highlight.self,
            Tag.self,
            Label.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appending(path: path), encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
