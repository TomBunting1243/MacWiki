import Foundation

/// Cache-invalidation keys for the directory column.
///
/// A missed input here leaves stale rows on screen. A needlessly broad input rebuilds the
/// directory snapshot when nothing visible changed. Keeping the hashing behind an explicit input
/// boundary makes both failure modes directly testable.
@MainActor
enum DirectoryFingerprint {
    /// Inputs that determine which articles the directory is showing.
    struct VisibleInputs {
        var articleIndexesFingerprint: Int
        var rootSelection: SidebarRootSelection
        var recentsScope: RecentsScope
        var selectedList: ReadingList?
        var selectedLabel: Label?
        var selectedTag: Tag?
        var localLabelFilter: Label?
        var localTagFilter: Tag?
        var supplementalReadFilter: DirectoryReadFilter
        var supplementalSortMode: DirectorySupplementalSortMode
        var availableLabelIDs: [UUID]
        var availableTagIDs: [UUID]
        var savedArticles: [SavedArticle]
        var articleStates: [ArticleState]
        var highlights: [Highlight]
        var activeTabID: UUID?
        var activeTabHistory: [HistoryItem]
        var activeTabCurrentIndex: Int?
        var recentArticles: [Article]
        /// Titles whose hydrated word counts affect ordering; empty unless sorting by length.
        var wordCountSensitiveTitles: [String]
        /// Resolves a hydrated word count for a title, or `nil` if it has not arrived yet.
        var hydratedWordCount: (String) -> Int?
    }

    /// Fingerprint of the directory's selection and ordering inputs.
    static func visible(_ inputs: VisibleInputs) -> Int {
        var hasher = Hasher()
        hasher.combine(inputs.articleIndexesFingerprint)
        hasher.combine(inputs.rootSelection.rawValue)
        hasher.combine(inputs.recentsScope.rawValue)
        hasher.combine(inputs.selectedList?.id)
        hasher.combine(inputs.selectedLabel?.id)
        hasher.combine(inputs.selectedTag?.id)
        hasher.combine(inputs.localLabelFilter?.id)
        hasher.combine(inputs.localTagFilter?.id)
        hasher.combine(inputs.supplementalReadFilter == .unread)
        hasher.combine(inputs.supplementalSortMode.rawValue)

        for id in inputs.availableLabelIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }
        for id in inputs.availableTagIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            hasher.combine(id)
        }

        combineScopeContents(into: &hasher, inputs: inputs)

        for title in inputs.wordCountSensitiveTitles {
            hasher.combine(ReadStateSync.normalizedTitle(title))
            hasher.combine(inputs.hydratedWordCount(title))
        }

        return hasher.finalize()
    }

    /// Hashes exactly one content collection using the existing invalidation precedence: list,
    /// label, tag, resolved current-tab history, then global recents.
    private static func combineScopeContents(into hasher: inout Hasher, inputs: VisibleInputs) {
        if let list = inputs.selectedList {
            hasher.combine(list.filterMode.rawValue)
            hasher.combine(list.sortMode.rawValue)
            hasher.combine(list.articles.count)
            for article in list.articles {
                hasher.combine(article.id)
                hasher.combine(article.manualOrder)
            }
        } else if let label = inputs.selectedLabel {
            hasher.combine(label.id)
            let labeledIDs = inputs.savedArticles
                .filter { $0.labelId == label.id }
                .map(\.id)
                .sorted { $0.uuidString < $1.uuidString }
            hasher.combine(labeledIDs.count)
            for id in labeledIDs {
                hasher.combine(id)
            }
        } else if let tag = inputs.selectedTag {
            let tagTitles = DirectorySnapshotBuilder.taggedArticleTitles(
                for: tag,
                articleStates: inputs.articleStates,
                highlights: inputs.highlights
            )
            hasher.combine(tag.id)
            hasher.combine(tagTitles.count)
            for title in tagTitles {
                hasher.combine(ReadStateSync.normalizedTitle(title))
            }
        } else if inputs.recentsScope == .currentTab, let activeTabID = inputs.activeTabID {
            hasher.combine(activeTabID)
            hasher.combine(inputs.activeTabCurrentIndex)
            hasher.combine(inputs.activeTabHistory.count)
            for item in inputs.activeTabHistory {
                hasher.combine(item.id)
                hasher.combine(item.article.title)
                hasher.combine(item.article.isRead)
            }
        } else {
            hasher.combine(inputs.recentArticles.count)
            for article in inputs.recentArticles {
                hasher.combine(article.id)
                hasher.combine(article.title)
                hasher.combine(article.isRead)
            }
        }
    }
}
