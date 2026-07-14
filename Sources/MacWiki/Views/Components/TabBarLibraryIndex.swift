import Foundation

/// A render-local index for the tab strip's library adornments.
///
/// SwiftData can invalidate `TabBarView` for unrelated row and scroll changes.
/// Keeping the normalized title maps behind a semantic revision prevents every
/// redraw from walking every saved article and highlight again.
@MainActor
final class TabBarLibraryIndex {
    struct Snapshot {
        let savedArticleByTitle: [String: SavedArticle]
        let highlightedTitles: Set<String>
    }

    private struct ReadingListRevision: Equatable {
        let id: UUID
        let updatedAt: Date
        let articleCount: Int
    }

    private struct HighlightRevision: Equatable {
        let id: UUID
        let updatedAt: Date
        let isArchived: Bool
    }

    private struct Revision: Equatable {
        let readingLists: [ReadingListRevision]
        let highlights: [HighlightRevision]
    }

    private var revision: Revision?
    private var cachedSnapshot = Snapshot(
        savedArticleByTitle: [:],
        highlightedTitles: []
    )
    private(set) var rebuildCount = 0

    func snapshot(
        lists: [ReadingList],
        highlights: [Highlight]
    ) -> Snapshot {
        let nextRevision = Revision(
            readingLists: lists.map {
                ReadingListRevision(
                    id: $0.id,
                    updatedAt: $0.updatedAt,
                    articleCount: $0.articles.count
                )
            },
            highlights: highlights.map {
                HighlightRevision(
                    id: $0.id,
                    updatedAt: $0.updatedAt,
                    isArchived: $0.isArchived
                )
            }
        )

        guard nextRevision != revision else { return cachedSnapshot }

        var savedArticleByTitle: [String: SavedArticle] = [:]
        for list in lists {
            for article in list.articles {
                let title = ReadStateSync.normalizedTitle(article.title)
                if savedArticleByTitle[title] == nil {
                    savedArticleByTitle[title] = article
                }
            }
        }

        let highlightedTitles = Set(
            highlights.lazy
                .filter { !$0.isArchived }
                .map { ReadStateSync.normalizedTitle($0.articleTitle) }
        )

        revision = nextRevision
        cachedSnapshot = Snapshot(
            savedArticleByTitle: savedArticleByTitle,
            highlightedTitles: highlightedTitles
        )
        rebuildCount += 1
        return cachedSnapshot
    }
}
