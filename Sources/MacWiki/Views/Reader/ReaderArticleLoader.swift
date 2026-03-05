import Foundation

@MainActor
final class ReaderArticleLoader {
    struct FastContent {
        let html: String
        let metadata: [WikipediaService.MetadataItem]
        let wordCount: Int
        let source: WikipediaService.FastArticleSource

        var isWarmCacheHit: Bool {
            switch source {
            case .network:
                return false
            case .memoryFull, .memoryFast, .disk:
                return true
            }
        }
    }

    private let wikipediaService: WikipediaService
    private let maxMetadataHydrationHTMLBytes: Int
    private var metadataHydrationTask: Task<Void, Never>?
    private var pinSyncTask: Task<Void, Never>?

    init(
        wikipediaService: WikipediaService = .shared,
        maxMetadataHydrationHTMLBytes: Int = 900_000
    ) {
        self.wikipediaService = wikipediaService
        self.maxMetadataHydrationHTMLBytes = maxMetadataHydrationHTMLBytes
    }

    func cancelPendingMetadataHydration() {
        metadataHydrationTask?.cancel()
        metadataHydrationTask = nil
    }

    func cancelPendingPinSync() {
        pinSyncTask?.cancel()
        pinSyncTask = nil
    }

    func fetchFastContent(forTitle title: String, forceRefresh: Bool = false) async throws -> FastContent {
        let result: (content: WikipediaService.ArticleContent, source: WikipediaService.FastArticleSource)
        if forceRefresh {
            result = try await wikipediaService.refreshArticleFastDetailed(title)
        } else {
            result = try await wikipediaService.fetchArticleFastDetailed(title)
        }
        let content = result.content
        return FastContent(
            html: content.html,
            metadata: content.metadata,
            wordCount: content.wordCount,
            source: result.source
        )
    }

    func scheduleMetadataHydration(
        for article: Article,
        html: String,
        wordCount: Int,
        applyEnrichedMetadata: @escaping @MainActor (WikipediaService.HydratedMetadata) -> Void
    ) {
        cancelPendingMetadataHydration()
        guard html.utf8.count <= maxMetadataHydrationHTMLBytes else { return }

        let articleTitle = article.title
        metadataHydrationTask = Task(priority: .utility) { [wikipediaService] in
            let enriched = await wikipediaService.fetchArticleMetadata(
                articleTitle,
                html: html,
                wordCount: wordCount
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                applyEnrichedMetadata(enriched)
            }
        }
    }

    func setPinned(_ pinned: Bool, forArticleTitle title: String) async {
        await wikipediaService.setArticlePinned(title, pinned: pinned)
    }

    func schedulePinSync(_ pinned: Bool, forArticleTitle title: String) {
        pinSyncTask?.cancel()
        pinSyncTask = Task(priority: .utility) { [wikipediaService] in
            guard !Task.isCancelled else { return }
            await wikipediaService.setArticlePinned(title, pinned: pinned)
        }
    }
}
