import Foundation
import SwiftUI

extension AppState {
    func setNavigationColumnsVisible(_ isVisible: Bool) {
        navigationSplitViewVisibility = isVisible ? .all : .detailOnly
    }

    func toggleListsSidebarVisibility() {
        guard !isWikiHopNavigationLocked else { return }

        switch navigationSplitViewVisibility {
        case .all, .automatic:
            navigationSplitViewVisibility = .doubleColumn
        case .doubleColumn, .detailOnly:
            navigationSplitViewVisibility = .all
        default:
            navigationSplitViewVisibility = .all
        }
    }

    func setNavigationSplitViewVisibility(listsVisible: Bool, directoryVisible: Bool) {
        switch (listsVisible, directoryVisible) {
        case (true, true):
            navigationSplitViewVisibility = .all
        case (false, true):
            navigationSplitViewVisibility = .doubleColumn
        case (false, false):
            navigationSplitViewVisibility = .detailOnly
        case (true, false):
            navigationSplitViewVisibility = .all
        }
    }

    /// Current scroll position for a specific tab id.
    ///
    /// When `historyItemID` is provided, this resolves against that specific
    /// history entry rather than the tab's current index. This prevents late
    /// telemetry from an outgoing article from mutating the incoming article's
    /// initial scroll slot during same-tab navigations.
    func scrollPosition(forTabID id: UUID, historyItemID: UUID? = nil) -> CGFloat {
        guard let tabIndex = openTabs.firstIndex(where: { $0.id == id }) else { return 0 }
        let tab = openTabs[tabIndex]

        if let historyItemID,
           let historyIndex = tab.history.firstIndex(where: { $0.id == historyItemID }) {
            return tab.history[historyIndex].scrollPosition
        }
        return tab.scrollPosition
    }

    /// Update scroll position for a specific tab id.
    ///
    /// See `scrollPosition(forTabID:historyItemID:)` for why we optionally bind
    /// writes to a specific history entry.
    func setScrollPosition(_ position: CGFloat, forTabID id: UUID, historyItemID: UUID? = nil) {
        guard let tabIndex = openTabs.firstIndex(where: { $0.id == id }) else { return }
        var tabs = openTabs
        var tab = tabs[tabIndex]

        if let historyItemID,
           let historyIndex = tab.history.firstIndex(where: { $0.id == historyItemID }) {
            tab.updateHistoryItem(at: historyIndex) { $0.scrollPosition = position }
            tabs[tabIndex] = tab
            openTabs = tabs
            return
        }

        tab.scrollPosition = position
        tabs[tabIndex] = tab
        openTabs = tabs
    }

    /// Update read status for the current article in the active tab history.
    func setReadStatusForCurrentArticle(_ isRead: Bool) {
        guard let activeId = activeTabId,
              let index = openTabs.firstIndex(where: { $0.id == activeId }) else {
            return
        }
        guard let articleTitle = openTabs[index].currentArticle?.title else { return }
        updateReadState(forTitle: articleTitle, isRead: isRead)
    }

    /// Open an article in a new tab or navigate in current.
    func openArticle(_ article: Article, inNewTab: Bool = false, activateNewTab: Bool = true) {
        if isOpenArticleMutationInFlight {
            pendingOpenArticleRequest = PendingOpenArticleRequest(
                article: article,
                inNewTab: inNewTab,
                activateNewTab: activateNewTab
            )
            return
        }

        isOpenArticleMutationInFlight = true
        defer {
            isOpenArticleMutationInFlight = false
            if let pending = pendingOpenArticleRequest {
                pendingOpenArticleRequest = nil
                DispatchQueue.main.async { [weak self] in
                    self?.openArticle(
                        pending.article,
                        inNewTab: pending.inNewTab,
                        activateNewTab: pending.activateNewTab
                    )
                }
            }
        }

        let normalizedTargetTitle = ReadStateSync.normalizedTitle(article.title)
        let signature = "\(normalizedTargetTitle)|\(inNewTab ? "1" : "0")|\(activateNewTab ? "1" : "0")|\(activeTabId?.uuidString ?? "none")"
        let now = Date().timeIntervalSinceReferenceDate
        if signature == lastOpenArticleSignature, (now - lastOpenArticleTimestamp) < 0.8 {
            return
        }
        lastOpenArticleSignature = signature
        lastOpenArticleTimestamp = now

        if isWikiHopNavigationLocked && inNewTab {
            return
        }

        let result = tabSessionStore.openArticle(
            article,
            inNewTab: inNewTab,
            activateNewTab: activateNewTab
        )

        if let openedArticle = result.openedArticle {
            if isWikiHopNavigationLocked && !inNewTab {
                if checkWikiHopWin(title: openedArticle.title) {
                    completeWikiHop()
                } else {
                    incrementWikiHopClicks(currentTitle: openedArticle.title)
                }
            }

            scheduleRecentUpdate(for: openedArticle)
        }
    }

    /// Convenience method to open article in a new tab.
    func openArticleInNewTab(_ article: Article, activate: Bool = true) {
        openArticle(article, inNewTab: true, activateNewTab: activate)
    }

    /// Presents the option-click save flow for a clicked article.
    func presentOptionClickSavePrompt(for article: Article) {
        optionClickSaveRequest = OptionClickSaveRequest(
            id: UUID(),
            article: article
        )
    }

    /// Presents the option-click save flow for the article in the active reader tab.
    func presentOptionClickSavePromptForCurrentArticle() {
        guard let article = currentArticle else { return }
        presentOptionClickSavePrompt(for: article)
    }

    /// Dismisses the option-click save flow.
    func dismissOptionClickSavePrompt() {
        optionClickSaveRequest = nil
    }

    /// Create a new empty tab page.
    func createNewTab() {
        tabSessionStore.createNewTab()
    }

    /// Navigate back in current tab.
    func goBack() {
        tabSessionStore.goBack()
    }

    /// Navigate forward in current tab.
    func goForward() {
        tabSessionStore.goForward()
    }

    /// Remove an article from recent history.
    func removeFromRecent(_ article: Article) {
        recentArticles.removeAll { $0.id == article.id }
        save()
    }

    /// Clear all duplicates from recent history, normalized by title.
    func deduplicateRecents() {
        var seen = Set<String>()
        recentArticles = recentArticles.filter { article in
            let normalized = article.title.lowercased().replacingOccurrences(of: "_", with: " ")
            if seen.contains(normalized) {
                return false
            }
            seen.insert(normalized)
            return true
        }
        save()
    }

    func addToRecent(_ article: Article) {
        recentArticles.removeAll { $0.id == article.id }
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        recentArticles.removeAll {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }
        recentArticles.insert(article, at: 0)
        if recentArticles.count > 50 {
            recentArticles.removeLast()
        }
    }

    func scheduleRecentUpdate(for article: Article) {
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        pendingRecentArticles.removeAll {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }
        pendingRecentArticles.append(article)

        guard recentUpdateWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let pending = self.pendingRecentArticles
            self.pendingRecentArticles.removeAll()
            self.recentUpdateWorkItem = nil
            for pendingArticle in pending {
                self.addToRecent(pendingArticle)
            }
            self.requestSave()
        }
        recentUpdateWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    /// Switch to next tab.
    func nextTab() {
        tabSessionStore.nextTab()
    }

    /// Switch to previous tab.
    func previousTab() {
        tabSessionStore.previousTab()
    }

    /// Close currently active tab.
    func closeActiveTab() {
        tabSessionStore.closeActiveTab()
    }

    /// Close a tab by ID.
    func closeTab(_ id: UUID) {
        tabSessionStore.closeTab(id)
    }

    /// Reopen the most recently closed tab (Command-Shift-T).
    func reopenLastClosedTab() {
        tabSessionStore.reopenLastClosedTab()
    }

    /// Duplicate the active tab, preserving its history stack and position.
    func duplicateActiveTab() {
        guard let activeTabId else { return }
        tabSessionStore.duplicateTab(id: activeTabId)
    }

    /// Legacy duplicate entry point kept while call sites migrate.
    func duplicateTab(with article: Article) {
        if let activeTabId {
            tabSessionStore.duplicateTab(id: activeTabId)
        } else {
            _ = tabSessionStore.openArticle(article, inNewTab: true, activateNewTab: true)
        }
    }

    /// Close all tabs except the one with given ID.
    func closeOtherTabs(keeping id: UUID) {
        tabSessionStore.closeOtherTabs(keeping: id)
    }

    /// Move a tab from one position to another.
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        tabSessionStore.moveTab(from: sourceIndex, to: destinationIndex)
    }

    /// Start a search with specific context.
    func startSearch(context: SearchContext) {
        self.searchContext = context
        showSearch = true
    }

    func consumeLaunchSidebarSearchQuery() -> String? {
        defer { launchSidebarSearchQuery = nil }
        guard let raw = launchSidebarSearchQuery?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Toggle inspector visibility with a single shared state transition path.
    /// Keeping this centralized avoids divergent behavior between toolbar and menu actions.
    func toggleInspectorVisibility() {
        inspectorVisible.toggle()
    }

    /// Show the Discover page in the reader column.
    /// Reuses an existing new-tab/discover tab when possible.
    func showDiscoverPage() {
        tabSessionStore.showDiscoverPage()
    }

    func resetOpenArticleMutationState() {
        lastOpenArticleSignature = nil
        lastOpenArticleTimestamp = 0
        isOpenArticleMutationInFlight = false
        pendingOpenArticleRequest = nil
    }
}
