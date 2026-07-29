import SwiftData
import SwiftUI

struct SidebarSearchResultRowView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    let row: SidebarSearchRow
    let isSelected: Bool
    let selectedTagId: UUID?
    let allLists: [ReadingList]
    let allLabels: [Label]
    let allTags: [Tag]
    let onOpenRow: (SidebarSearchRow, Bool) -> Void
    let onToggleRead: (SidebarSearchRow) -> Void
    let onLabelClick: (Label) -> Void
    let onTagClick: (Tag) -> Void
    let onShowPageViews: () -> Void

    private var dragPayload: SavedArticleDragPayload {
        if let savedArticle = row.savedArticle {
            return SavedArticleDragPayload(
                savedArticleID: savedArticle.id,
                sourceListID: savedArticle.readingList?.id,
                title: savedArticle.title,
                articleDescription: row.article.description,
                extract: row.article.extract,
                thumbnailURL: row.article.thumbnailURL,
                isRead: row.isRead,
                wordCount: row.resolvedWordCount
            )
        }

        return SavedArticleDragPayload(
            title: row.article.title,
            articleDescription: row.article.description,
            extract: row.article.extract,
            thumbnailURL: row.article.thumbnailURL,
            isRead: row.isRead,
            wordCount: row.resolvedWordCount
        )
    }

    var body: some View {
        ArticleListItem(
            accessibilityTitle: row.article.title,
            isRead: row.isRead,
            progress: row.readingProgress,
            isCurrent: row.isCurrent,
            isSelected: isSelected,
            label: row.label,
            onToggleRead: {
                onToggleRead(row)
            },
            onTap: {
                onOpenRow(row, SystemBridge.isCommandPressed)
            }
        ) { isHovered, label in
            ArticleRowWithFetch(
                article: row.article,
                hydratedMetadata: row.hydratedMetadata,
                isHovered: isHovered,
                label: label,
                onLabelClick: onLabelClick,
                listName: row.savedArticle?.readingList?.name,
                listIconName: row.savedArticle?.readingList?.icon,
                tags: row.tags,
                selectedTagId: selectedTagId,
                onTagClick: onTagClick
            )
        }
        .contextMenu {
            articleContextMenu
        }
        .draggable(dragPayload) {
            SwiftUI.Label(row.article.title, systemImage: "doc.text")
                .macWikiDragPreviewSurface()
        }
    }

    private var articleContextMenu: some View {
        ArticleContextMenuContent(
            article: row.article,
            isRead: row.isRead,
            currentTags: row.tags,
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
            onOpen: {
                onOpenRow(row, false)
            },
            onOpenInNewTab: {
                onOpenRow(row, true)
            },
            onShowPageViews: onShowPageViews
        )
    }
}
