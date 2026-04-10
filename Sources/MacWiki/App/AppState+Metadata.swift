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
        var didChange = false

        for index in recentArticles.indices where ids.contains(recentArticles[index].id) {
            if let description, recentArticles[index].description != description {
                recentArticles[index].description = description
                didChange = true
            }
            if let extract, recentArticles[index].extract != extract {
                recentArticles[index].extract = extract
                didChange = true
            }
            if let wordCount, recentArticles[index].wordCount != wordCount {
                recentArticles[index].wordCount = wordCount
                didChange = true
            }
        }

        var tabs = openTabs
        for tabIndex in tabs.indices {
            for historyIndex in tabs[tabIndex].history.indices {
                let article = tabs[tabIndex].history[historyIndex].article
                guard ids.contains(article.id) else { continue }

                tabs[tabIndex].updateHistoryItem(at: historyIndex) { item in
                    if let description, item.article.description != description {
                        item.article.description = description
                        didChange = true
                    }
                    if let extract, item.article.extract != extract {
                        item.article.extract = extract
                        didChange = true
                    }
                    if let wordCount, item.article.wordCount != wordCount {
                        item.article.wordCount = wordCount
                        didChange = true
                    }
                }
            }
        }
        openTabs = tabs

        if didChange {
            requestSave()
        }
    }

    /// Update read status across recents and all tab history items matching title.
    func updateReadState(forTitle title: String, isRead: Bool) {
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for index in recentArticles.indices {
            let candidate = recentArticles[index].title
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate == normalized {
                recentArticles[index].isRead = isRead
            }
        }

        var tabs = openTabs
        for tabIndex in tabs.indices {
            for historyIndex in tabs[tabIndex].history.indices {
                let candidate = tabs[tabIndex].history[historyIndex].article.title
                    .lowercased()
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate == normalized {
                    tabs[tabIndex].updateHistoryItem(at: historyIndex) { $0.article.isRead = isRead }
                }
            }
        }
        openTabs = tabs

        save()
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
