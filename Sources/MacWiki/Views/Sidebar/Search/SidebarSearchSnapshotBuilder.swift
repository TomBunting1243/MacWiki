import Foundation

@MainActor
enum SidebarSearchSnapshotBuilder {
    static func build(
        sourceResults: [WikipediaService.SearchResult],
        sourceKind: SidebarSearchSourceKind,
        readFilter: SidebarSearchReadFilter,
        sortMode: SidebarSearchSortMode,
        labelFilter: Label? = nil,
        tagFilter: Tag? = nil,
        articleIndexes: DirectoryArticleIndexes,
        labels: [Label],
        currentArticleTitleNormalized: String?,
        liveReadingProgress: (String) -> Double? = { _ in nil },
        metadataSnapshot: (String) -> ArticleMetadataHydrationSnapshot? = { _ in nil }
    ) -> SidebarSearchVisibleSnapshot {
        let rows = sourceResults.map { result in
            row(
                for: result,
                sourceKind: sourceKind,
                articleIndexes: articleIndexes,
                labels: labels,
                currentArticleTitleNormalized: currentArticleTitleNormalized,
                liveReadingProgress: liveReadingProgress,
                metadataSnapshot: metadataSnapshot
            )
        }

        let scopedRows = rows.filter { row in
            if let labelFilter, row.label?.id != labelFilter.id {
                return false
            }
            if let tagFilter, !row.tags.contains(where: { $0.id == tagFilter.id }) {
                return false
            }
            return true
        }

        let scopedCounts = scopedRows.reduce(into: (read: 0, unread: 0)) { result, row in
            if row.isRead {
                result.read += 1
            } else {
                result.unread += 1
            }
        }

        let filteredRows: [SidebarSearchRow]
        switch readFilter {
        case .all:
            filteredRows = scopedRows
        case .unread:
            filteredRows = scopedRows.filter { !$0.isRead }
        }

        let sortedRows = sorted(filteredRows, mode: sortMode)
        let counts = sortedRows.reduce(into: (read: 0, unread: 0)) { result, row in
            if row.isRead {
                result.read += 1
            } else {
                result.unread += 1
            }
        }

        return SidebarSearchVisibleSnapshot(
            sourceKind: sourceKind,
            rows: sortedRows,
            sourceCount: sourceResults.count,
            scopedCount: scopedRows.count,
            scopedReadCount: scopedCounts.read,
            scopedUnreadCount: scopedCounts.unread,
            visibleReadCount: counts.read,
            visibleUnreadCount: counts.unread
        )
    }

    static func rowID(
        for result: WikipediaService.SearchResult,
        sourceKind: SidebarSearchSourceKind
    ) -> String {
        "\(sourceKind.rawValue):\(ReadStateSync.normalizedTitle(result.title)):\(result.id)"
    }

    private static func row(
        for result: WikipediaService.SearchResult,
        sourceKind: SidebarSearchSourceKind,
        articleIndexes: DirectoryArticleIndexes,
        labels: [Label],
        currentArticleTitleNormalized: String?,
        liveReadingProgress: (String) -> Double?,
        metadataSnapshot: (String) -> ArticleMetadataHydrationSnapshot?
    ) -> SidebarSearchRow {
        let savedArticle = articleIndexes.savedArticle(for: result.title)
        let hydratedMetadata = metadataSnapshot(result.title)
        let resolvedWordCount = hydratedMetadata?.wordCount ?? savedArticle?.wordCount
        let article = Article(
            id: result.id,
            title: result.title,
            description: hydratedMetadata?.description ?? savedArticle?.articleDescription ?? result.description,
            extract: hydratedMetadata?.extract ?? savedArticle?.extract,
            thumbnailURL: hydratedMetadata?.thumbnailURL ?? savedArticle?.thumbnailURL ?? result.thumbnailURL,
            isRead: articleIndexes.effectiveReadState(for: result.title, fallback: savedArticle?.isRead ?? false),
            wordCount: resolvedWordCount
        )
        let normalizedTitle = ReadStateSync.normalizedTitle(result.title)
        let state = articleIndexes.articleState(for: result.title)
        let labelID = savedArticle?.labelId ?? state?.labelId
        let label = labelID.flatMap { id in labels.first { $0.id == id } }
        let isCurrent = currentArticleTitleNormalized == normalizedTitle
        let progress = (isCurrent ? liveReadingProgress(result.title) : nil) ?? state?.readingProgress ?? 0

        return SidebarSearchRow(
            id: rowID(for: result, sourceKind: sourceKind),
            result: result,
            article: article,
            hydratedMetadata: hydratedMetadata,
            savedArticle: savedArticle,
            label: label,
            tags: articleIndexes.tagsForArticle(title: result.title),
            isRead: article.isRead,
            readingProgress: progress,
            isCurrent: isCurrent,
            resolvedWordCount: resolvedWordCount
        )
    }

    private static func sorted(
        _ rows: [SidebarSearchRow],
        mode: SidebarSearchSortMode
    ) -> [SidebarSearchRow] {
        switch mode {
        case .relevance:
            return rows
        case .title:
            return rows.sorted {
                $0.article.title.localizedStandardCompare($1.article.title) == .orderedAscending
            }
        case .articleLength:
            return rows.sorted { lhs, rhs in
                let lhsCount = lhs.resolvedWordCount ?? -1
                let rhsCount = rhs.resolvedWordCount ?? -1
                if lhsCount != rhsCount {
                    return lhsCount > rhsCount
                }
                return lhs.article.title.localizedStandardCompare(rhs.article.title) == .orderedAscending
            }
        }
    }
}
