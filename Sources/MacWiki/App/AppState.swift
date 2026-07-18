import SwiftUI
import Observation
import os

let appStateLogger = Logger(subsystem: "com.macwiki", category: "appstate")

/// Controls whether an app-state graph participates in the user's shared on-disk session.
///
/// Secondary article windows, previews, and tests use `.ephemeral` so their local
/// navigation mutations can never overwrite the primary window's persisted state.
enum AppStatePersistenceMode: Equatable, Sendable {
    case shared
    case ephemeral

    var isEnabled: Bool {
        self == .shared
    }
}

/// Global application state container
/// 
/// Manages all shared state across the application including:
/// - Navigation state (active tab)
/// - UI state (sidebar visibility, inspector mode)
/// - Data collections (recent articles)
/// Note: Reading lists are managed via SwiftData, not AppState
@Observable @MainActor
final class AppState {
    let tabSessionStore: TabSessionStore

    /// One scene-owned Discover feed keeps the directory companion and the
    /// full editorial page on the same loading, error, and cache boundary.
    /// Individual surfaces still own their presentation state, but they no
    /// longer start competing network pipelines for the same edition.
    @ObservationIgnored
    let discoverFeedStore = DiscoverFeedStore()

    @ObservationIgnored
    let persistenceMode: AppStatePersistenceMode

    @ObservationIgnored
    let webViewPoolOwnerID = UUID()
    @ObservationIgnored
    var lastOpenArticleSignature: String?
    @ObservationIgnored
    var lastOpenArticleTimestamp: TimeInterval = 0
    @ObservationIgnored
    var isOpenArticleMutationInFlight = false
    @ObservationIgnored
    var pendingOpenArticleRequest: PendingOpenArticleRequest?

    struct PendingOpenArticleRequest {
        let article: Article
        let inNewTab: Bool
        let activateNewTab: Bool
    }

    // MARK: - Navigation
    
    /// All open article tabs
    var openTabs: [ArticleTab] {
        get { tabSessionStore.openTabs }
        set { tabSessionStore.openTabs = newValue }
    }

    /// ID of the currently active tab
    var activeTabId: UUID? {
        get { tabSessionStore.activeTabId }
        set { tabSessionStore.activeTabId = newValue }
    }

    /// Identity-only tab membership for consumers that do not render tab order.
    var openTabIDs: Set<UUID> {
        tabSessionStore.openTabIDs
    }

    var hasOpenTabs: Bool {
        !tabSessionStore.openTabIDs.isEmpty
    }
    
    // MARK: - UI State
    
    /// Platform-owned AppKit split items publish directly into these stored
    /// values. Lists and List Contents are independent panes; neither is a
    /// lossy projection of SwiftUI's three-column visibility enum.
    var listsSidebarVisible = true {
        didSet {
            if isWikiHopNavigationLocked, listsSidebarVisible {
                listsSidebarVisible = false
            }
        }
    }

    var directoryColumnVisible = true {
        didSet {
            if isWikiHopNavigationLocked, directoryColumnVisible {
                directoryColumnVisible = false
            }
        }
    }

    /// The user's inspector preference, bound directly to SwiftUI's inspector.
    var inspectorVisible: Bool = true

    /// Current inspector view mode
    var inspectorMode: InspectorMode = .info

    /// Shared Discover edition date for the directory and reader surfaces.
    /// This is session UI state and is intentionally not persisted to disk.
    var selectedDiscoverDate = Date()

    /// Table of contents entries for the currently displayed article
    var currentArticleTableOfContents: [ArticleTableOfContentsItem] = []

    /// Pending section id request to scroll the WebView to a heading
    var pendingTableOfContentsScrollTarget: String?

    /// Section currently nearest to viewport top in the reader
    var currentVisibleTableOfContentsSectionId: String?
    
    /// Whether the embedded List Contents search surface is shown.
    var showSearch: Bool = false

    // MARK: - Find on Page (Reader)

    /// Whether the in-page find UI is shown for the reader column.
    var showFindOnPage: Bool = false

    /// Changes whenever a command asks the visible find field to become key.
    /// Keeping focus intent separate from visibility lets repeated Command-F
    /// recover focus without rebuilding the reader overlay.
    var findOnPageFocusRequestID: UUID?

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

    /// Scene-scoped creation requests consumed by the active window's presentation surfaces.
    var newReadingListRequestID: UUID?
    var newFolderRequestID: UUID?
    var newArticleLabelRequest: NewArticleLabelRequest?
    var newArticleTagRequest: NewArticleTagRequest?

    /// Scene-scoped requests for reader presentations that may be hosted by
    /// either the main AppKit toolbar or a standalone article-window toolbar.
    var readerStylePresentationRequestID: UUID?
    var readerPageViewsPresentationRequestID: UUID?

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

    struct NewArticleLabelRequest: Identifiable, Equatable {
        let id: UUID
        let article: SavedArticle

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct NewArticleTagRequest: Identifiable, Equatable {
        let id: UUID
        let article: Article

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id
        }
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
    var recentlyClosedTabs: [ArticleTab] {
        get { tabSessionStore.recentlyClosedTabs }
        set { tabSessionStore.recentlyClosedTabs = newValue }
    }
    
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
    var articleHTMLCacheOrder: [String] = []
    @ObservationIgnored
    var articleHTMLCacheSizeByTitle: [String: Int] = [:]
    @ObservationIgnored
    var articleHTMLCacheTotalBytes: Int = 0
    @ObservationIgnored
    var pinnedArticleHTMLTitles: Set<String> = []
    @ObservationIgnored
    let maxArticleHTMLCacheEntries = 14
    @ObservationIgnored
    let maxArticleHTMLCacheBytes = 5_000_000
    @ObservationIgnored
    let maxArticleHTMLCacheEntryBytes = 900_000

    // MARK: - Wiki-Hop
    
    /// Current active or completed Wiki-Hop run
    var wikiHopSession: WikiHopSession?

    let wikiHopPostV1FeatureKey = AppStorageKey.Features.wikiHopPostV1Enabled

    // MARK: - Computed Properties

    var currentTab: ArticleTab? {
        tabSessionStore.currentTab
    }

    /// Narrow stored state for the active reader. Unlike `currentTab`, this does
    /// not observe the ordered tab collection and is stable across pure reorder.
    var activeReaderProjection: ActiveReaderProjection {
        tabSessionStore.activeReaderProjection
    }

    /// The currently displayed article (from active tab)
    var currentArticle: Article? {
        tabSessionStore.activeReaderProjection.article
    }

    var activeReaderHistoryItemID: UUID? {
        tabSessionStore.activeReaderProjection.historyItemID
    }

    var isActiveTabPlaceholder: Bool {
        tabSessionStore.activeReaderProjection.isPlaceholder
    }

    var canGoBack: Bool {
        tabSessionStore.activeReaderProjection.canGoBack
    }

    var canGoForward: Bool {
        tabSessionStore.activeReaderProjection.canGoForward
    }

    func requestNewReadingList() {
        newReadingListRequestID = UUID()
    }

    func requestNewFolder() {
        newFolderRequestID = UUID()
    }

    func requestNewArticleLabel(for article: SavedArticle) {
        newArticleLabelRequest = NewArticleLabelRequest(id: UUID(), article: article)
    }

    func requestNewArticleTag(for article: Article) {
        newArticleTagRequest = NewArticleTagRequest(id: UUID(), article: article)
    }

    init(persistenceMode: AppStatePersistenceMode = .shared) {
        self.persistenceMode = persistenceMode
        self.tabSessionStore = TabSessionStore(persistenceMode: persistenceMode)
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: ())
        if persistenceMode.isEnabled {
            load()
            deduplicateRecents()
        }
        synchronizeExperimentStateFromDefaults()
    }

    struct HighlightRehydrateRequest: Equatable {
        let id: UUID
        let text: String
        let cssColor: String
        let elementPath: String
        let startOffset: Int
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

    // MARK: - Persistence
    
    @ObservationIgnored
    var saveTask: Task<Void, Never>?
    @ObservationIgnored
    var recentUpdateWorkItem: DispatchWorkItem?
    @ObservationIgnored
    var pendingRecentArticles: [Article] = []
    @ObservationIgnored
    let persistenceQueue = DispatchQueue(label: "MacWiki.AppState.Persistence", qos: .utility)
    @ObservationIgnored
    let persistenceQueueKey = DispatchSpecificKey<Void>()
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
    var content: TabContent = .placeholder

    private enum CodingKeys: String, CodingKey {
        case id
        case content
        case history
        case currentIndex
        case isNewTab
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()

        if let content = try container.decodeIfPresent(TabContent.self, forKey: .content) {
            self.content = content
            return
        }

        let history = try container.decodeIfPresent([HistoryItem].self, forKey: .history) ?? []
        let currentIndex = try container.decodeIfPresent(Int.self, forKey: .currentIndex) ?? 0
        let isNewTab = try container.decodeIfPresent(Bool.self, forKey: .isNewTab) ?? history.isEmpty

        if isNewTab || history.isEmpty {
            self.content = .placeholder
        } else {
            self.content = .history(
                items: history,
                currentIndex: Self.clampedHistoryIndex(currentIndex, count: history.count)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(content, forKey: .content)
    }

    var history: [HistoryItem] {
        get {
            switch content {
            case .placeholder:
                return []
            case .history(let items, _):
                return items
            }
        }
        set {
            if newValue.isEmpty {
                content = .placeholder
            } else {
                content = .history(
                    items: newValue,
                    currentIndex: Self.clampedHistoryIndex(currentIndex, count: newValue.count)
                )
            }
        }
    }

    var currentIndex: Int {
        get {
            switch content {
            case .placeholder:
                return 0
            case .history(_, let currentIndex):
                return currentIndex
            }
        }
        set {
            switch content {
            case .placeholder:
                return
            case .history(let items, _):
                content = .history(
                    items: items,
                    currentIndex: Self.clampedHistoryIndex(newValue, count: items.count)
                )
            }
        }
    }

    var isPlaceholder: Bool {
        if case .placeholder = content {
            return true
        }
        return false
    }

    var isNewTab: Bool {
        isPlaceholder
    }

    // Proxy for current scroll position
    var scrollPosition: CGFloat {
        get {
            guard let currentHistoryItem else { return 0 }
            return currentHistoryItem.scrollPosition
        }
        set {
            updateCurrentHistoryItem { $0.scrollPosition = newValue }
        }
    }

    var currentHistoryItem: HistoryItem? {
        guard history.indices.contains(currentIndex) else { return nil }
        return history[currentIndex]
    }

    var currentArticle: Article? {
        currentHistoryItem?.article
    }

    var article: Article {
        get {
            guard let currentArticle else {
                preconditionFailure("Placeholder tabs do not contain an article")
            }
            return currentArticle
        }
    }

    init(article: Article) {
        self.content = .history(items: [HistoryItem(article: article)], currentIndex: 0)
    }

    init(id: UUID = UUID(), content: TabContent) {
        self.id = id
        self.content = content
    }

    /// Create an empty new tab
    init() {
        self.content = .placeholder
    }

    var title: String {
        currentArticle?.title ?? "Discover"
    }

    var canGoBack: Bool { currentIndex > 0 }
    var canGoForward: Bool { currentIndex < history.count - 1 }

    mutating func replacePlaceholder(with article: Article) {
        content = .history(items: [HistoryItem(article: article)], currentIndex: 0)
    }

    mutating func truncateForwardHistory() {
        guard case .history(let items, let currentIndex) = content,
              items.indices.contains(currentIndex),
              currentIndex < items.count - 1 else { return }
        content = .history(items: Array(items.prefix(currentIndex + 1)), currentIndex: currentIndex)
    }

    mutating func appendToHistory(_ article: Article) {
        switch content {
        case .placeholder:
            replacePlaceholder(with: article)
        case .history(let items, _):
            let updatedItems = items + [HistoryItem(article: article)]
            content = .history(items: updatedItems, currentIndex: updatedItems.count - 1)
        }
    }

    mutating func moveBack() {
        currentIndex -= 1
    }

    mutating func moveForward() {
        currentIndex += 1
    }

    mutating func updateHistoryItem(at index: Int, update: (inout HistoryItem) -> Void) {
        guard case .history(var items, let currentIndex) = content,
              items.indices.contains(index) else { return }
        update(&items[index])
        content = .history(items: items, currentIndex: Self.clampedHistoryIndex(currentIndex, count: items.count))
    }

    mutating func updateCurrentHistoryItem(update: (inout HistoryItem) -> Void) {
        updateHistoryItem(at: currentIndex, update: update)
    }

    func duplicated() -> ArticleTab {
        var duplicate = ArticleTab()
        duplicate.id = UUID()
        duplicate.content = content
        return duplicate
    }

    private static func clampedHistoryIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
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
