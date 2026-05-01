import Foundation

extension AppState {
    /// Update article metadata (description, extract, wordCount) in recents and tab history.
    func updateArticleMetadata(id: String, description: String?, extract: String?, wordCount: Int?) {
        updateArticleMetadata(
            ids: [id],
            description: description,
            extract: extract,
            wordCount: wordCount
        )
    }

    /// Batch update article metadata across recents and tab history with one save request.
    func updateArticleMetadata(ids: Set<String>, description: String?, extract: String?, wordCount: Int?) {
        guard !ids.isEmpty else { return }
        var didChangeRecents = false

        for index in recentArticles.indices where ids.contains(recentArticles[index].id) {
            if let description, recentArticles[index].description != description {
                recentArticles[index].description = description
                didChangeRecents = true
            }
            if let extract, recentArticles[index].extract != extract {
                recentArticles[index].extract = extract
                didChangeRecents = true
            }
            if let wordCount, recentArticles[index].wordCount != wordCount {
                recentArticles[index].wordCount = wordCount
                didChangeRecents = true
            }
        }

        tabSessionStore.updateArticleMetadata(
            ids: ids,
            description: description,
            extract: extract,
            wordCount: wordCount
        )

        if didChangeRecents {
            requestSave()
        }
    }

    /// Update read status across recents and all tab history items matching title.
    func updateReadState(forTitle title: String, isRead: Bool) {
        let normalized = ReadStateSync.normalizedTitle(title)
        var didChangeRecents = false

        for index in recentArticles.indices {
            let candidate = ReadStateSync.normalizedTitle(recentArticles[index].title)
            if candidate == normalized {
                if recentArticles[index].isRead != isRead {
                    recentArticles[index].isRead = isRead
                    didChangeRecents = true
                }
            }
        }

        tabSessionStore.updateReadState(forTitle: title, isRead: isRead)

        if didChangeRecents {
            requestSave()
        }
    }

    func resetArticlePresentationState() {
        currentArticleTableOfContents.removeAll()
        pendingTableOfContentsScrollTarget = nil
        currentVisibleTableOfContentsSectionId = nil
        currentArticleMetadata.removeAll()
        currentArticleReferences.removeAll()
        selectedReferenceId = nil
    }
}
