import SwiftData
import SwiftUI

struct SavedArticleRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let savedArticle: SavedArticle
    var hydratedMetadata: ArticleMetadataHydrationSnapshot? = nil
    let isRead: Bool
    let readProgress: Double
    var isCurrent: Bool = false
    let list: ReadingList?
    let allLists: [ReadingList]
    let allLabels: [Label]

    let onToggleRead: () -> Void
    let onMove: (ReadingList) -> Void
    let onRemove: (() -> Void)?
    var onLabelClick: ((Label) -> Void)? = nil
    var tags: [Tag] = []
    var allTags: [Tag] = []
    var selectedTagId: UUID? = nil
    var onTagClick: ((Tag) -> Void)? = nil
    var isSelected: Bool = false
    var onOpenArticle: ((Article) -> Void)? = nil
    let onNewLabel: (SavedArticle) -> Void
    var onNewTag: ((Article) -> Void)? = nil

    @State private var showingPageViewsPopover = false

    private var currentLabel: Label? {
        allLabels.first { $0.id == savedArticle.labelId }
    }

    var body: some View {
        let resolvedDescription = hydratedMetadata?.description ?? savedArticle.articleDescription
        let resolvedExtract = hydratedMetadata?.extract ?? savedArticle.extract
        let resolvedThumbnailURL = hydratedMetadata?.thumbnailURL ?? savedArticle.thumbnailURL
        let resolvedWordCount = hydratedMetadata?.wordCount ?? savedArticle.wordCount
        let article = Article(
            id: savedArticle.title,
            title: savedArticle.title,
            description: resolvedDescription,
            extract: resolvedExtract,
            thumbnailURL: resolvedThumbnailURL,
            isRead: isRead,
            wordCount: resolvedWordCount
        )

        ArticleListItem(
            isRead: isRead,
            progress: readProgress,
            isCurrent: isCurrent,
            isSelected: isSelected,
            label: currentLabel,
            onToggleRead: onToggleRead,
            onTap: {
                if let onOpenArticle {
                    onOpenArticle(article)
                } else {
                    if SystemBridge.isOptionPressed {
                        appState.presentOptionClickSavePrompt(for: article)
                        return
                    }
                    appState.openArticle(article, inNewTab: SystemBridge.isCommandPressed)
                }
            }
        ) { isHovered, label in
            ArticleRow(
                article: article,
                extract: resolvedExtract,
                allowsEstimatedWordCount: false,
                isHovered: isHovered,
                label: label,
                onLabelClick: onLabelClick,
                tags: tags,
                selectedTagId: selectedTagId,
                onTagClick: onTagClick
            )
        }
        .contextMenu {
            ArticleContextMenuContent(
                title: savedArticle.title,
                description: resolvedDescription,
                extract: resolvedExtract,
                thumbnailURL: resolvedThumbnailURL,
                isRead: isRead,
                currentLabelId: savedArticle.labelId,
                currentTags: tags,
                savedArticle: savedArticle,
                currentList: list,
                allLabels: allLabels,
                allTags: allTags,
                allLists: allLists,
                onToggleRead: onToggleRead,
                onSetLabel: { labelId in
                    ArticleLibraryActions.applyLabel(
                        labelId,
                        to: [savedArticle],
                        modelContext: modelContext
                    )
                },
                onNewLabel: { onNewLabel(savedArticle) },
                onToggleTag: { tag in
                    ArticleLibraryActions.toggleTag(
                        tag,
                        for: article,
                        modelContext: modelContext
                    )
                },
                onNewTag: {
                    onNewTag?(article)
                },
                onOpenInNewTab: {
                    appState.openArticleInNewTab(article)
                },
                onShowPageViews: {
                    showingPageViewsPopover = true
                },
                onMoveToList: list != nil ? { targetList in onMove(targetList) } : nil,
                onAddToList: { targetList in
                    ArticleLibraryActions.addSavedArticle(
                        savedArticle,
                        to: targetList,
                        modelContext: modelContext
                    )
                },
                onRemove: onRemove,
                onCopyTitle: { ArticleLinkActions.copyTitle(article.title) },
                onCopyLink: { ArticleLinkActions.copyWikipediaLink(forTitle: article.title) }
            )
        }
        .popover(isPresented: $showingPageViewsPopover, arrowEdge: .trailing) {
            SidebarPageViewsPopoverContent(
                title: article.title,
                referenceDate: Date()
            )
        }
        .draggable(savedArticle.id.uuidString) {
            SwiftUI.Label(savedArticle.title, systemImage: "doc.text")
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
