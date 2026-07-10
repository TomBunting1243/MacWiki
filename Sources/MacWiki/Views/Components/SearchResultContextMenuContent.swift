import SwiftUI
import SwiftData

struct SearchResultContextMenuContent: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let result: WikipediaService.SearchResult
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let onOpen: (Bool) -> Void
    var onShowPageViews: (() -> Void)? = nil

    private var article: Article {
        Article(
            id: result.id,
            title: result.title,
            description: result.description,
            thumbnailURL: result.thumbnailURL
        )
    }

    var body: some View {
        ArticleContextMenuContent(
            article: article,
            isRead: ReadStateSync.resolveReadState(for: article, in: modelContext),
            currentTags: [],
            allLabels: allLabels,
            allTags: allTags,
            allLists: allLists,
            modelContext: modelContext,
            appState: appState,
            onNewLabel: { savedArticle in
                appState.requestNewArticleLabel(for: savedArticle)
            },
            onNewTag: { article in
                appState.requestNewArticleTag(for: article)
            },
            onOpen: { onOpen(false) },
            onOpenInNewTab: { onOpen(true) },
            onShowPageViews: onShowPageViews
        )
    }
}
