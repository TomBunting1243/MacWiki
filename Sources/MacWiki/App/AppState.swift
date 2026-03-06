import SwiftUI
import Observation
import os

private let appStateLogger = Logger(subsystem: "com.macwiki", category: "appstate")

/// Global application state container
/// 
/// Manages all shared state across the application including:
/// - Navigation state (active tab)
/// - UI state (sidebar visibility, inspector mode)
/// - Data collections (recent articles)
/// Note: Reading lists are managed via SwiftData, not AppState
@Observable @MainActor
final class AppState {
    @ObservationIgnored
    private var lastOpenArticleSignature: String?
    @ObservationIgnored
    private var lastOpenArticleTimestamp: TimeInterval = 0
    @ObservationIgnored
    private var isOpenArticleMutationInFlight = false
    @ObservationIgnored
    private var pendingOpenArticleRequest: PendingOpenArticleRequest?
    @ObservationIgnored
    private var focusModeSidebarRestoreValue: Bool?
    @ObservationIgnored
    private var focusModeInspectorRestoreValue: Bool?

    private struct PendingOpenArticleRequest {
        let article: Article
        let inNewTab: Bool
        let activateNewTab: Bool
    }

    // MARK: - Navigation
    
    /// All open article tabs
    var openTabs: [ArticleTab] = []
    
    /// ID of the currently active tab
    var activeTabId: UUID?
    
    // MARK: - UI State
    
    /// Whether the lists sidebar is visible
    var sidebarVisible: Bool = true
    
    /// Whether the inspector panel is visible
    var inspectorVisible: Bool = true
    
    /// Current inspector view mode
    var inspectorMode: InspectorMode = .info

    /// Reader-first mode that hides side columns and top reader chrome.
    var isFocusModeEnabled: Bool = false

    /// Table of contents entries for the currently displayed article
    var currentArticleTableOfContents: [ArticleTableOfContentsItem] = []

    /// Pending section id request to scroll the WebView to a heading
    var pendingTableOfContentsScrollTarget: String?

    /// Section currently nearest to viewport top in the reader
    var currentVisibleTableOfContentsSectionId: String?
    
    /// Whether the search UI is shown (floating overlay or sidebar, based on settings)
    var showSearch: Bool = false

    // MARK: - Find on Page (Reader)

    /// Whether the in-page find UI is shown for the reader column.
    var showFindOnPage: Bool = false

    /// Current find query for in-page search.
    var findOnPageQuery: String = ""

    /// Best-effort match signal from the most recent WebKit find call.
    /// `nil` indicates no active query (or query cleared).
    var findOnPageMatchFound: Bool?

    /// Best-effort total match count from the most recent WebKit find call.
    /// `nil` indicates no active query (or query cleared) or that the count has not arrived yet.
    var findOnPageMatchCount: Int?

    /// Pending in-page find request to be executed by the active tab's `WKWebView`.
    var pendingFindOnPageRequest: FindOnPageRequest?

    /// Tracks the most recent find request ID so stale async results can be ignored.
    var currentFindOnPageRequestID: UUID?
    
    /// Whether the Add to List popover is shown (⌘L)
    var showAddToList: Bool = false

    /// Pending request to save a clicked article link with list/tag/label metadata.
    var optionClickSaveRequest: OptionClickSaveRequest?

    /// Height obscured by window titlebar/toolbar when full-size content is enabled.
    /// Side columns use this to stay clear of chrome while the reader can underflow.
    var windowTopObscuredHeight: CGFloat = 38

    /// Context in which the search was triggered
    var searchContext: SearchContext = .navigation

    /// One-shot query seed used by launch-driven QA harnesses.
    /// Consumed by sidebar search on first appearance after launch.
    var launchSidebarSearchQuery: String?

    struct FindOnPageRequest: Equatable {
        let requestID: UUID
        let tabID: UUID
        let query: String
        let backwards: Bool
    }

    struct OptionClickSaveRequest: Identifiable, Equatable {
        let id: UUID
        let article: Article
    }

    // MARK: - Highlighting

    /// Text pending highlight creation (from ⌘H shortcut)
    var pendingHighlightText: String?

    /// Currently selected highlight ID (for editing/deleting)
    var selectedHighlightId: String?

    /// Current text selection data (for showing highlight toolbar)
    var currentTextSelection: TextSelectionData?

    /// Pending immediate highlight to apply to DOM.
    /// Set this to trigger WebView to call highlightCurrentSelection JS.
    var pendingImmediateHighlight: ImmediateHighlightRequest?

    /// Pending request to retry rehydrating a stale highlight
    var pendingHighlightRehydrate: HighlightRehydrateRequest?

    /// Result of the most recent rehydrate attempt
    var lastHighlightRehydrateResult: HighlightRehydrateResult?

    /// Indicates a rehydrate attempt is currently in progress
    var isHighlightRehydrateInProgress: Bool = false

    /// Pending request to force-refresh the current article for highlight reconciliation.
    var pendingHighlightArticleRefresh: HighlightArticleRefreshRequest?

    /// Indicates an article refresh for highlight reconciliation is currently in progress.
    var isHighlightArticleRefreshInProgress: Bool = false

    /// Result of the most recent article refresh for highlight reconciliation.
    var lastHighlightArticleRefreshResult: HighlightArticleRefreshResult?

    /// Pending request to update a highlight color in the WebView
    var pendingHighlightColorChange: HighlightColorChangeRequest?

    /// Pending request to scroll to a highlight in the WebView
    var pendingHighlightScroll: UUID?

    /// Pending request to open a highlight row directly in note-edit mode.
    var pendingHighlightNoteEditorRequest: HighlightNoteEditorRequest?

    /// Active tag filter for highlights list
    var highlightTagFilterId: UUID?
    
    // MARK: - Data
    
    /// Recently viewed articles
    /// Recently viewed articles
    var recentArticles: [Article] = []

    /// Recently closed tabs (LIFO), used for reopen action
    var recentlyClosedTabs: [ArticleTab] = []
    
    /// Metadata for the currently open article
    var currentArticleMetadata: [WikipediaService.MetadataItem] = []

    /// References for the currently open article, grouped by section.
    var currentArticleReferences: [ArticleReferenceSection] = []

    /// Currently focused reference id (for inspector list focus).
    var selectedReferenceId: String?

    /// Live reading progress for currently interacted articles (normalized title -> progress).
    /// Used to keep list indicators responsive while SwiftData catches up.
    var liveReadingProgressByTitle: [String: Double] = [:]

    /// In-memory article HTML cache keyed by normalized title.
    /// Avoids unnecessary reload/fetch churn when switching tabs.
    var articleHTMLCacheByTitle: [String: String] = [:]
    @ObservationIgnored
    private var articleHTMLCacheOrder: [String] = []
    @ObservationIgnored
    private var articleHTMLCacheSizeByTitle: [String: Int] = [:]
    @ObservationIgnored
    private var articleHTMLCacheTotalBytes: Int = 0
    @ObservationIgnored
    private var pinnedArticleHTMLTitles: Set<String> = []
    @ObservationIgnored
    private let maxArticleHTMLCacheEntries = 14
    @ObservationIgnored
    private let maxArticleHTMLCacheBytes = 5_000_000
    @ObservationIgnored
    private let maxArticleHTMLCacheEntryBytes = 900_000

    // MARK: - Wiki-Hop
    
    /// Current active or completed Wiki-Hop run
    var wikiHopSession: WikiHopSession?

    private let wikiHopPostV1FeatureKey = "features.wikiHopPostV1Enabled"

    private var isWikiHopPostV1FeatureEnabled: Bool {
        UserDefaults.standard.bool(forKey: wikiHopPostV1FeatureKey)
    }

    private var isWikiHopExperimentEnabled: Bool {
        UserDefaults.standard.bool(forKey: ExperimentFlag.wikiHopPOCEnabled.key)
    }

    private var isWikiHopRuntimeEnabled: Bool {
        isWikiHopPostV1FeatureEnabled && isWikiHopExperimentEnabled
    }
    
    var isWikiHopNavigationLocked: Bool {
        wikiHopSession?.status == .active
    }
    
    func startWikiHop(mode: WikiHopSession.Mode, start: Article, target: Article) {
        wikiHopSession = WikiHopSession(mode: mode, startArticle: start, targetArticle: target)
        // Ensure we handle navigation safely - usually the view layer will trigger the open
        // forcing a new session overrides any previous one
    }
    
    func failWikiHop(reason: String) {
        guard var session = wikiHopSession, session.status == .active else { return }
        session.status = .failed
        session.failureReason = reason
        session.completedAt = Date()
        wikiHopSession = session
        save() // Persist failure state
    }
    
    func completeWikiHop() {
        guard var session = wikiHopSession, session.status == .active else { return }
        session.status = .completed
        session.completedAt = Date()
        wikiHopSession = session
        save() // Persist completion state
    }
    
    func incrementWikiHopClicks(currentTitle: String) {
        guard var session = wikiHopSession, session.status == .active else { return }
        
        // Don't count reloads of same page
        let normalizedCurrent = ReadStateSync.normalizedTitle(session.currentTitle)
        let normalizedNew = ReadStateSync.normalizedTitle(currentTitle)
        
        if normalizedCurrent != normalizedNew {
            session.clickCount += 1
            session.currentTitle = currentTitle
            wikiHopSession = session
            save()
        }
    }
    
    func updateWikiHopCurrentTitle(_ title: String) {
        guard var session = wikiHopSession else { return }
        session.currentTitle = title
        wikiHopSession = session
    }
    
    /// Check if the title matches the target (resolving redirects if we had that data, but here we just check title)
    func checkWikiHopWin(title: String) -> Bool {
        guard let session = wikiHopSession, session.status == .active else { return false }
        return ReadStateSync.normalizedTitle(title) == ReadStateSync.normalizedTitle(session.targetArticle.title)
    }

    /// Dismisses any active/completed Wiki-Hop session and removes lock/overlay state.
    func dismissWikiHopSession() {
        guard wikiHopSession != nil else { return }
        wikiHopSession = nil
        save()
    }

    /// Centralized settings entry point for Wiki-Hop experiment state changes.
    func setWikiHopExperimentEnabled(_ isEnabled: Bool) {
        let resolvedEnabled = isEnabled && isWikiHopPostV1FeatureEnabled
        UserDefaults.standard.set(resolvedEnabled, forKey: ExperimentFlag.wikiHopPOCEnabled.key)
        applyWikiHopExperimentState(isEnabled: resolvedEnabled)
    }

    /// Applies experiment gates to runtime state using current persisted defaults.
    func synchronizeExperimentStateFromDefaults() {
        if !isWikiHopPostV1FeatureEnabled, isWikiHopExperimentEnabled {
            UserDefaults.standard.set(false, forKey: ExperimentFlag.wikiHopPOCEnabled.key)
        }
        applyWikiHopExperimentState(isEnabled: isWikiHopRuntimeEnabled)
    }

    private func applyWikiHopExperimentState(isEnabled: Bool) {
        guard !isEnabled else { return }
        dismissWikiHopSession()
        enforceDiscoverStartModeFallbackIfNeeded()
    }

    private func enforceDiscoverStartModeFallbackIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: DiscoverStartMode.storageKey) == DiscoverStartMode.wikiHop.rawValue else {
            return
        }
        defaults.set(DiscoverStartMode.discoverFeed.rawValue, forKey: DiscoverStartMode.storageKey)
    }

    // MARK: - Computed Properties
    
    /// The currently displayed article (from active tab)
    var currentArticle: Article? {
        guard let activeId = activeTabId,
              let tab = openTabs.first(where: { $0.id == activeId }),
              !tab.isNewTab else {
            return nil
        }
        return tab.article
    }

    /// Current scroll position for a specific tab id.
    ///
    /// When `historyItemID` is provided, this resolves against that specific
    /// history entry rather than the tab's current index. This prevents late
    /// telemetry from an outgoing article from mutating the incoming article's
    /// initial scroll slot during same-tab navigations.
    func scrollPosition(forTabID id: UUID, historyItemID: UUID? = nil) -> CGFloat {
        guard let tabIndex = openTabs.firstIndex(where: { $0.id == id }) else { return 0 }

        if let historyItemID,
           let historyIndex = openTabs[tabIndex].history.firstIndex(where: { $0.id == historyItemID }) {
            return openTabs[tabIndex].history[historyIndex].scrollPosition
        }

        return openTabs[tabIndex].scrollPosition
    }

    /// Update scroll position for a specific tab id.
    ///
    /// See `scrollPosition(forTabID:historyItemID:)` for why we optionally bind
    /// writes to a specific history entry.
    func setScrollPosition(_ position: CGFloat, forTabID id: UUID, historyItemID: UUID? = nil) {
        guard let tabIndex = openTabs.firstIndex(where: { $0.id == id }) else { return }

        if let historyItemID,
           let historyIndex = openTabs[tabIndex].history.firstIndex(where: { $0.id == historyItemID }) {
            openTabs[tabIndex].history[historyIndex].scrollPosition = position
            return
        }

        openTabs[tabIndex].scrollPosition = position
    }

    /// Update read status for the current article in the active tab history
    func setReadStatusForCurrentArticle(_ isRead: Bool) {
        guard let activeId = activeTabId,
              let index = openTabs.firstIndex(where: { $0.id == activeId }) else {
            return
        }
        let tab = openTabs[index]
        guard tab.history.indices.contains(tab.currentIndex) else { return }
        let articleTitle = tab.history[tab.currentIndex].article.title
        updateReadState(forTitle: articleTitle, isRead: isRead)
    }
    
    init() {
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: ())
        load()
        deduplicateRecents()
        synchronizeExperimentStateFromDefaults()
    }

    struct HighlightRehydrateRequest: Equatable {
        let id: UUID
        let text: String
        let cssColor: String
        let contextBefore: String
        let contextAfter: String
    }

    struct HighlightRehydrateResult: Equatable {
        let id: UUID
        let success: Bool
        let timestamp: Date
    }

    struct HighlightArticleRefreshRequest: Equatable {
        let id: UUID
        let articleTitle: String
    }

    struct HighlightArticleRefreshResult: Equatable {
        let requestId: UUID
        let articleTitle: String
        let success: Bool
        let timestamp: Date
    }

    struct HighlightColorChangeRequest: Equatable {
        let id: UUID
        let cssColor: String
    }

    struct ImmediateHighlightRequest: Equatable {
        let id: UUID
        let cssColor: String
    }

    struct HighlightNoteEditorRequest: Equatable {
        let requestID: UUID
        let highlightID: UUID
    }

    // MARK: - Actions
    
    /// Open an article in a new tab or navigate in current
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

        // Wiki-Hop Guard: Prevent New Tabs
        if isWikiHopNavigationLocked && inNewTab {
            return
        }

        // 1. Force New Tab
        if inNewTab {
            var updatedTabs = openTabs
            let tab = ArticleTab(article: article)
            updatedTabs.append(tab)
            openTabs = updatedTabs
            if activateNewTab || activeTabId == nil {
                activeTabId = tab.id
            }
            requestSave()
            scheduleRecentUpdate(for: article)
            return
        }

        // 2. Navigate in Current Tab (if exists)
        if let activeId = activeTabId,
           let index = openTabs.firstIndex(where: { $0.id == activeId }) {
            
            // Wiki-Hop Logic
            if isWikiHopNavigationLocked {
                 if checkWikiHopWin(title: article.title) {
                     completeWikiHop()
                 } else {
                     incrementWikiHopClicks(currentTitle: article.title)
                 }
            }

            var updatedTabs = openTabs
            var tab = updatedTabs[index]

            // If current tab is a "new tab" page, convert it to an article tab
            if tab.isNewTab {
                tab.isNewTab = false
                tab.history = [HistoryItem(article: article)]
                tab.currentIndex = 0
                updatedTabs[index] = tab
                openTabs = updatedTabs
                requestSave()
                scheduleRecentUpdate(for: article)
                return
            }

            // If same article, do nothing
            if ReadStateSync.normalizedTitle(tab.article.title) == normalizedTargetTitle { return }

            // Truncate forward history if we navigated back then opened new link
            let currentIndex = tab.currentIndex
            let historyCount = tab.history.count
            if currentIndex < historyCount - 1 && currentIndex >= 0 {
                tab.history = Array(tab.history.prefix(currentIndex + 1))
            }

            // Push new article
            tab.history.append(HistoryItem(article: article))
            tab.currentIndex = tab.history.count - 1
            updatedTabs[index] = tab
            openTabs = updatedTabs
            // Scroll position for new item is 0 by default

            requestSave()
            scheduleRecentUpdate(for: article)
        } else {
            // 3. Fallback: No active tab, create new
            var updatedTabs = openTabs
            let tab = ArticleTab(article: article)
            updatedTabs.append(tab)
            openTabs = updatedTabs
            activeTabId = tab.id
            requestSave()
            scheduleRecentUpdate(for: article)
        }
    }

    /// Convenience method to open article in a new tab
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

    /// Create a new empty tab page
    func createNewTab() {
        let tab = ArticleTab()
        openTabs.append(tab)
        activeTabId = tab.id
        disableFocusModeIfUnavailable()
        requestSave()
    }
    
    /// Navigate back in current tab
    func goBack() {
        guard let index = openTabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        var tab = openTabs[index]

        guard tab.canGoBack, tab.history.indices.contains(tab.currentIndex - 1) else { return }
        tab.currentIndex -= 1
        openTabs[index] = tab
        save()
    }

    /// Navigate forward in current tab
    func goForward() {
        guard let index = openTabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        var tab = openTabs[index]

        guard tab.canGoForward, tab.history.indices.contains(tab.currentIndex + 1) else { return }
        tab.currentIndex += 1
        openTabs[index] = tab
        save()
    }
    
    /// Remove an article from recent history
    func removeFromRecent(_ article: Article) {
        recentArticles.removeAll { $0.id == article.id }
        save()
    }

    /// Clear all duplicates from recent history (normalize by title)
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

    /// Update article metadata (description, extract, wordCount) in recents and tab history
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

        for tabIndex in openTabs.indices {
            for historyIndex in openTabs[tabIndex].history.indices {
                guard ids.contains(openTabs[tabIndex].history[historyIndex].article.id) else { continue }

                if let description,
                   openTabs[tabIndex].history[historyIndex].article.description != description {
                    openTabs[tabIndex].history[historyIndex].article.description = description
                    didChange = true
                }
                if let extract,
                   openTabs[tabIndex].history[historyIndex].article.extract != extract {
                    openTabs[tabIndex].history[historyIndex].article.extract = extract
                    didChange = true
                }
                if let wordCount,
                   openTabs[tabIndex].history[historyIndex].article.wordCount != wordCount {
                    openTabs[tabIndex].history[historyIndex].article.wordCount = wordCount
                    didChange = true
                }
            }
        }

        if didChange {
            requestSave()
        }
    }

    /// Update read status across recents and all tab history items matching title
    func updateReadState(forTitle title: String, isRead: Bool) {
        let normalized = title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Update recents
        for index in recentArticles.indices {
            let candidate = recentArticles[index].title
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate == normalized {
                recentArticles[index].isRead = isRead
            }
        }

        // Update tab history across all tabs
        for tabIndex in openTabs.indices {
            for historyIndex in openTabs[tabIndex].history.indices {
                let candidate = openTabs[tabIndex].history[historyIndex].article.title
                    .lowercased()
                    .replacingOccurrences(of: "_", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate == normalized {
                    openTabs[tabIndex].history[historyIndex].article.isRead = isRead
                }
            }
        }

        save()
    }

    private func addToRecent(_ article: Article) {
        // Remove by exact ID first
        recentArticles.removeAll { $0.id == article.id }
        // Also remove by normalized title to catch variants
        let normalizedTitle = ReadStateSync.normalizedTitle(article.title)
        recentArticles.removeAll {
            ReadStateSync.normalizedTitle($0.title) == normalizedTitle
        }
        recentArticles.insert(article, at: 0)
        if recentArticles.count > 50 {
            recentArticles.removeLast()
        }
    }

    private func scheduleRecentUpdate(for article: Article) {
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
    
    /// Switch to next tab
    func nextTab() {
        guard !openTabs.isEmpty, let currentId = activeTabId,
              let currentIndex = openTabs.firstIndex(where: { $0.id == currentId }) else { return }
        
        let nextIndex = (currentIndex + 1) % openTabs.count
        activeTabId = openTabs[nextIndex].id
        disableFocusModeIfUnavailable()
        save()
    }
    
    /// Switch to previous tab
    func previousTab() {
        guard !openTabs.isEmpty, let currentId = activeTabId,
              let currentIndex = openTabs.firstIndex(where: { $0.id == currentId }) else { return }
        
        let prevIndex = (currentIndex - 1 + openTabs.count) % openTabs.count
        activeTabId = openTabs[prevIndex].id
        disableFocusModeIfUnavailable()
        save()
    }
    
    /// Close currently active tab
    func closeActiveTab() {
        guard let currentId = activeTabId else { return }
        closeTab(currentId)
    }
    
    /// Close a tab by ID
    func closeTab(_ id: UUID) {
        guard let closedIndex = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let closedTab = openTabs.remove(at: closedIndex)

        // Keep a small stack for "Reopen Closed Tab"
        recentlyClosedTabs.append(closedTab)
        if recentlyClosedTabs.count > 20 {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - 20)
        }

        // If we closed the active tab, prefer neighbor tab at same index
        if activeTabId == id {
            if openTabs.isEmpty {
                activeTabId = nil
            } else {
                let fallbackIndex = min(closedIndex, openTabs.count - 1)
                activeTabId = openTabs[fallbackIndex].id
            }
        }
        disableFocusModeIfUnavailable()
        save()
    }

    /// Reopen the most recently closed tab (⌘⇧T)
    func reopenLastClosedTab() {
        guard let tab = recentlyClosedTabs.popLast() else { return }
        openTabs.append(tab)
        activeTabId = tab.id
        disableFocusModeIfUnavailable()
        save()
    }
    
    /// Duplicate a tab with the given article
    func duplicateTab(with article: Article) {
        openArticle(article, inNewTab: true)
    }
    
    /// Close all tabs except the one with given ID
    func closeOtherTabs(keeping id: UUID) {
        let toClose = openTabs.filter { $0.id != id }
        if !toClose.isEmpty {
            recentlyClosedTabs.append(contentsOf: toClose)
            if recentlyClosedTabs.count > 20 {
                recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - 20)
            }
        }
        openTabs.removeAll { $0.id != id }
        activeTabId = id
        disableFocusModeIfUnavailable()
        save()
    }
    
    /// Move a tab from one position to another
    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              openTabs.indices.contains(sourceIndex),
              destinationIndex >= 0, destinationIndex <= openTabs.count else { return }

        let tab = openTabs.remove(at: sourceIndex)
        // Destination is a final target index from tab-drag logic, not List.onMove semantics.
        // Keep it direct so adjacent left-to-right drops commit correctly.
        let clampedIndex = max(0, min(destinationIndex, openTabs.count))
        openTabs.insert(tab, at: clampedIndex)
        save()
    }
    
    /// Start a search with specific context
    func startSearch(context: SearchContext) {
        guard !isFocusModeEnabled else { return }
        self.searchContext = context
        self.showSearch = true
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
        guard !isFocusModeEnabled else { return }
        inspectorVisible.toggle()
    }

    func toggleFocusMode() {
        setFocusModeEnabled(!isFocusModeEnabled)
    }

    func setFocusModeEnabled(_ isEnabled: Bool) {
        guard isFocusModeEnabled != isEnabled else { return }

        if isEnabled {
            guard currentArticle != nil else { return }
            focusModeSidebarRestoreValue = sidebarVisible
            focusModeInspectorRestoreValue = inspectorVisible
            isFocusModeEnabled = true
            sidebarVisible = false
            inspectorVisible = false
            showSearch = false
            showFindOnPage = false
            findOnPageQuery = ""
            findOnPageMatchFound = nil
            findOnPageMatchCount = nil
            if let tabID = activeTabId {
                let clearRequest = FindOnPageRequest(
                    requestID: UUID(),
                    tabID: tabID,
                    query: "",
                    backwards: false
                )
                pendingFindOnPageRequest = clearRequest
                currentFindOnPageRequestID = clearRequest.requestID
            } else {
                pendingFindOnPageRequest = nil
                currentFindOnPageRequestID = nil
            }
            return
        }

        isFocusModeEnabled = false
        if let restoreSidebar = focusModeSidebarRestoreValue {
            sidebarVisible = restoreSidebar
        }
        if let restoreInspector = focusModeInspectorRestoreValue {
            inspectorVisible = restoreInspector
        }
        focusModeSidebarRestoreValue = nil
        focusModeInspectorRestoreValue = nil
    }

    func setLiveReadingProgress(forTitle title: String, progress: Double) {
        let key = ReadStateSync.normalizedTitle(title)
        let clamped = min(max(progress, 0), 1)
        if let current = liveReadingProgressByTitle[key], abs(current - clamped) < 0.01 {
            return
        }
        liveReadingProgressByTitle[key] = clamped
    }

    func liveReadingProgress(forTitle title: String) -> Double? {
        liveReadingProgressByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func setArticleHTMLPinned(_ pinned: Bool, forTitle title: String) {
        let key = ReadStateSync.normalizedTitle(title)
        if pinned {
            pinnedArticleHTMLTitles.insert(key)
        } else {
            pinnedArticleHTMLTitles.remove(key)
        }
        trimArticleHTMLCacheIfNeeded()
    }

    func cacheArticleHTML(_ html: String, forTitle title: String) {
        let key = ReadStateSync.normalizedTitle(title)
        let byteCount = html.utf8.count

        // Very large documents are expensive to retain repeatedly in-process.
        // Keep them in service/network cache paths, but skip this UI-level cache.
        if byteCount > maxArticleHTMLCacheEntryBytes {
            removeArticleHTMLCacheEntry(forKey: key)
            return
        }

        if let existingBytes = articleHTMLCacheSizeByTitle[key] {
            articleHTMLCacheTotalBytes -= existingBytes
        }

        articleHTMLCacheByTitle[key] = html
        articleHTMLCacheSizeByTitle[key] = byteCount
        articleHTMLCacheTotalBytes += byteCount
        articleHTMLCacheOrder.removeAll { $0 == key }
        articleHTMLCacheOrder.append(key)
        trimArticleHTMLCacheIfNeeded()
    }

    func cachedArticleHTML(forTitle title: String) -> String? {
        let key = ReadStateSync.normalizedTitle(title)
        guard let cached = articleHTMLCacheByTitle[key] else { return nil }
        articleHTMLCacheOrder.removeAll { $0 == key }
        articleHTMLCacheOrder.append(key)
        return cached
    }

    private func trimArticleHTMLCacheIfNeeded() {
        while articleHTMLCacheOrder.count > maxArticleHTMLCacheEntries ||
              articleHTMLCacheTotalBytes > maxArticleHTMLCacheBytes {
            guard let evictKey = articleHTMLCacheOrder.first(where: { !pinnedArticleHTMLTitles.contains($0) }) ??
                    articleHTMLCacheOrder.first else { break }
            removeArticleHTMLCacheEntry(forKey: evictKey)
        }
    }

    private func removeArticleHTMLCacheEntry(forKey key: String) {
        if let existingBytes = articleHTMLCacheSizeByTitle.removeValue(forKey: key) {
            articleHTMLCacheTotalBytes -= existingBytes
        }
        articleHTMLCacheByTitle.removeValue(forKey: key)
        articleHTMLCacheOrder.removeAll { $0 == key }
    }

    /// Show the Discover page in the reader column.
    /// Reuses an existing new-tab/discover tab when possible.
    func showDiscoverPage() {
        if let existingDiscoverTab = openTabs.first(where: { $0.isNewTab }) {
            activeTabId = existingDiscoverTab.id
            disableFocusModeIfUnavailable()
            save()
            return
        }
        createNewTab()
    }

    private func disableFocusModeIfUnavailable() {
        guard isFocusModeEnabled else { return }
        guard currentArticle == nil else { return }
        setFocusModeEnabled(false)
    }

    /// Reset app-level runtime + persisted navigation/state to defaults.
    /// SwiftData model deletion and cache clears are handled by the caller.
    func resetForFactoryDefaults() {
        saveTask?.cancel()
        recentUpdateWorkItem?.cancel()
        saveTask = nil
        recentUpdateWorkItem = nil
        pendingRecentArticles.removeAll()

        lastOpenArticleSignature = nil
        lastOpenArticleTimestamp = 0
        isOpenArticleMutationInFlight = false
        pendingOpenArticleRequest = nil

        openTabs.removeAll()
        activeTabId = nil
        recentlyClosedTabs.removeAll()
        recentArticles.removeAll()
        wikiHopSession = nil

        sidebarVisible = true
        inspectorVisible = true
        inspectorMode = .info
        isFocusModeEnabled = false
        focusModeSidebarRestoreValue = nil
        focusModeInspectorRestoreValue = nil
        showSearch = false
        showFindOnPage = false
        findOnPageQuery = ""
        findOnPageMatchFound = nil
        findOnPageMatchCount = nil
        pendingFindOnPageRequest = nil
        currentFindOnPageRequestID = nil
        showAddToList = false
        searchContext = .navigation

        currentArticleTableOfContents.removeAll()
        pendingTableOfContentsScrollTarget = nil
        currentVisibleTableOfContentsSectionId = nil
        currentArticleMetadata.removeAll()
        currentArticleReferences.removeAll()
        selectedReferenceId = nil

        pendingHighlightText = nil
        selectedHighlightId = nil
        currentTextSelection = nil
        pendingImmediateHighlight = nil
        pendingHighlightRehydrate = nil
        lastHighlightRehydrateResult = nil
        isHighlightRehydrateInProgress = false
        pendingHighlightArticleRefresh = nil
        isHighlightArticleRefreshInProgress = false
        lastHighlightArticleRefreshResult = nil
        pendingHighlightColorChange = nil
        pendingHighlightScroll = nil
        pendingHighlightNoteEditorRequest = nil
        highlightTagFilterId = nil

        liveReadingProgressByTitle.removeAll()
        articleHTMLCacheByTitle.removeAll()
        articleHTMLCacheOrder.removeAll()
        articleHTMLCacheSizeByTitle.removeAll()
        articleHTMLCacheTotalBytes = 0
        pinnedArticleHTMLTitles.removeAll()

        if let url = persistenceURL {
            try? FileManager.default.removeItem(at: url)
            let backup = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backup)
        }

        performSave(sync: true)
    }
    
    // MARK: - Persistence
    
    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private var recentUpdateWorkItem: DispatchWorkItem?
    @ObservationIgnored
    private var pendingRecentArticles: [Article] = []
    @ObservationIgnored
    private let persistenceQueue = DispatchQueue(label: "MacWiki.AppState.Persistence", qos: .utility)
    @ObservationIgnored
    private let persistenceQueueKey = DispatchSpecificKey<Void>()
    
    /// Request a state save (debounced)
    func requestSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    /// Flush pending state to disk immediately (used for lifecycle transitions).
    func flushSaveNow() {
        saveTask?.cancel()
        performSave(sync: true)
    }
    
    @MainActor
    private func performSave() {
        save()
    }

    @MainActor
    private func performSave(sync: Bool) {
        save(sync: sync)
    }
    
    private enum SavedStateLoadResult {
        case missing
        case success(SavedState, byteCount: Int)
        case failure(Error, byteCount: Int?)
    }

    private struct SavedState: Codable {
        let openTabs: [ArticleTab]
        let activeTabId: UUID?
        let recentArticles: [Article]
        let wikiHopSession: WikiHopSession?
    }
    
    private func save() {
        save(sync: false)
    }

    private func save(sync: Bool) {
        let state = SavedState(
            openTabs: openTabs,
            activeTabId: activeTabId,
            recentArticles: recentArticles,
            wikiHopSession: wikiHopSession
        )

        let targetURL = persistenceURL

        if sync {
            if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
                Self.writeState(state, to: targetURL)
            } else {
                persistenceQueue.sync {
                    Self.writeState(state, to: targetURL)
                }
            }
        } else {
            persistenceQueue.async { [state] in
                Self.writeState(state, to: targetURL)
            }
        }
    }

    nonisolated private static func writeState(_ state: SavedState, to url: URL?) {
        guard let url else { return }
        do {
            let text = try JSONEncoder().encode(state)
            try text.write(to: url, options: [.atomic])
        } catch {
            appStateLogger.error("Failed to save state: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func load() {
        guard let url = persistenceURL else { return }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()

        let loadResult: SavedStateLoadResult
        if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
            loadResult = Self.readSavedState(from: url)
        } else {
            loadResult = persistenceQueue.sync {
                Self.readSavedState(from: url)
            }
        }

        switch loadResult {
        case .missing:
            return
        case .success(let state, let byteCount):
            self.openTabs = state.openTabs
            self.activeTabId = state.activeTabId
            self.recentArticles = state.recentArticles

            // Restore session but invalidate Rush mode if it was active (session rules)
            if var session = state.wikiHopSession {
                if session.mode == .rush && session.status == .active {
                    session.status = .failed
                    session.failureReason = "Run canceled (app closed during Rush)"
                    session.completedAt = Date()
                }
                self.wikiHopSession = session
            }

            // Validate activeTabId references an existing tab
            if let activeId = self.activeTabId,
               !openTabs.contains(where: { $0.id == activeId }) {
                activeTabId = openTabs.first?.id
            }
            disableFocusModeIfUnavailable()
            PerformanceMetricsStore.shared.record(
                kind: .sessionRestore,
                durationMs: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
                detail: "tabs=\(openTabs.count) recents=\(recentArticles.count) bytes=\(byteCount)"
            )
        case .failure(let error, let byteCount):
            // Backup corrupted file for debugging, then start fresh
            appStateLogger.error("Failed to decode state; starting fresh: \(error.localizedDescription, privacy: .public)")
            let backup = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            PerformanceMetricsStore.shared.record(
                kind: .sessionRestore,
                durationMs: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
                detail: "failed bytes=\(byteCount ?? 0)"
            )
        }
    }

    nonisolated private static func readSavedState(from url: URL) -> SavedStateLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missing
        }

        do {
            let data = try Data(contentsOf: url)
            do {
                let state = try JSONDecoder().decode(SavedState.self, from: data)
                return .success(state, byteCount: data.count)
            } catch {
                return .failure(error, byteCount: data.count)
            }
        } catch {
            return .failure(error, byteCount: nil)
        }
    }
    
    private var persistenceURL: URL? {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let appDir = supportDir.appendingPathComponent("MacWiki")
        
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        return appDir.appendingPathComponent("state.json")
    }
}

// MARK: - Supporting Types

/// Represents an open article tab
// MARK: - Supporting Types

/// Represents a history state
struct HistoryItem: Codable, Hashable {
    var id: UUID = UUID()
    var article: Article
    var scrollPosition: CGFloat = 0
}

/// Represents an open article tab
struct ArticleTab: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var history: [HistoryItem] = []
    var currentIndex: Int = 0
    var isNewTab: Bool = false  // True when this is an empty "new tab" page

    // Proxy for current scroll position
    var scrollPosition: CGFloat {
        get {
            guard history.indices.contains(currentIndex) else { return 0 }
            return history[currentIndex].scrollPosition
        }
        set {
            if history.indices.contains(currentIndex) {
                history[currentIndex].scrollPosition = newValue
            }
        }
    }

    // Proxy for current article
    var article: Article {
        get {
            if history.indices.contains(currentIndex) {
                return history[currentIndex].article
            }
            return Article(id: "new-tab", title: "New Tab") // Fallback/new tab
        }
        set {
            // Read-only proxy
        }
    }

    init(article: Article) {
        self.history = [HistoryItem(article: article)]
        self.currentIndex = 0
        self.isNewTab = false
    }

    /// Create an empty new tab
    init() {
        self.history = []
        self.currentIndex = 0
        self.isNewTab = true
    }

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < history.count - 1 }
}

/// Inspector panel view modes
enum InspectorMode: String, CaseIterable {
    case info = "Info"
    case notes = "Notes"
    case references = "References"
    
    /// SF Symbol name for inactive state.
    var iconName: String {
        switch self {
        case .info: return "info.circle"
        case .notes: return "note.text"
        case .references: return "books.vertical"
        }
    }

    /// SF Symbol name for active state.
    var selectedIconName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .notes: return "note.text"
        case .references: return "books.vertical.fill"
        }
    }
}

/// Context for search activation
enum SearchContext {
    case navigation // Standard navigation (Cmd+K)
    case newTab     // New tab creation (Cmd+T, + button)
}
