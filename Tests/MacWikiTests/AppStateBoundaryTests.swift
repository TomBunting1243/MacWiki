import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct AppStateBoundaryTests {
    @Test func repeatedFindPresentationIssuesFreshFocusRequests() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.presentFindOnPage()
        let firstRequest = appState.findOnPageFocusRequestID
        appState.findOnPageMatchFound = true
        appState.presentFindOnPage()

        #expect(appState.showFindOnPage)
        #expect(firstRequest != nil)
        #expect(appState.findOnPageFocusRequestID != firstRequest)
        #expect(appState.findOnPageMatchFound == nil)

        appState.dismissFindOnPage(activeTabID: nil, clearsWebSelection: false)
        #expect(appState.findOnPageFocusRequestID == nil)
    }

    @Test func creationRequestsAreTypedSceneScopedAndRepeatable() {
        let appState = AppState(persistenceMode: .ephemeral)
        let savedArticle = SavedArticle(title: "Ada Lovelace")
        let article = Article(id: "swift", title: "Swift")

        appState.requestNewReadingList()
        let firstListRequest = appState.newReadingListRequestID
        appState.requestNewReadingList()
        appState.requestNewFolder()
        appState.requestNewArticleLabel(for: savedArticle)
        appState.requestNewArticleTag(for: article)

        #expect(firstListRequest != nil)
        #expect(appState.newReadingListRequestID != firstListRequest)
        #expect(appState.newFolderRequestID != nil)
        #expect(appState.newArticleLabelRequest?.article === savedArticle)
        #expect(appState.newArticleTagRequest?.article == article)
    }

    @Test func ephemeralStateGraphNeverSchedulesPersistentWrites() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.requestSave()
        appState.tabSessionStore.requestSave()

        #expect(appState.persistenceMode == .ephemeral)
        #expect(appState.tabSessionStore.persistenceMode == .ephemeral)
        #expect(appState.saveTask == nil)
        #expect(appState.tabSessionStore.hasPendingSaveForTesting == false)

        appState.flushSaveNow()

        #expect(appState.saveTask == nil)
        #expect(appState.tabSessionStore.hasPendingSaveForTesting == false)
    }

    @Test func listContentsTogglePreservesTheNativeNavigationHierarchy() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.setNavigationColumnsVisible(true)

        appState.toggleDirectoryColumnVisibility()

        #expect(appState.listsSidebarVisible == false)
        #expect(appState.directoryColumnVisible == false)
        #expect(appState.navigationSplitViewVisibility == .detailOnly)

        appState.toggleDirectoryColumnVisibility()

        #expect(appState.listsSidebarVisible == false)
        #expect(appState.directoryColumnVisible == true)
        #expect(appState.navigationSplitViewVisibility == .doubleColumn)
    }

    @Test func listsCanHideIndependentlyButShowingThemAlsoShowsListContents() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.setNavigationColumnsVisible(true)

        appState.toggleListsSidebarVisibility()

        #expect(appState.listsSidebarVisible == false)
        #expect(appState.directoryColumnVisible == true)
        #expect(appState.navigationSplitViewVisibility == .doubleColumn)

        appState.toggleListsSidebarVisibility()

        #expect(appState.listsSidebarVisible == true)
        #expect(appState.directoryColumnVisible == true)
        #expect(appState.navigationSplitViewVisibility == .all)
    }

    @Test func invalidNavigationCombinationNormalizesToReaderOnly() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.setNavigationColumnVisibility(
            listsVisible: true,
            directoryVisible: false
        )

        #expect(appState.workspaceNavigationColumns == .readerOnly)
        #expect(!appState.listsSidebarVisible)
        #expect(!appState.directoryColumnVisible)
    }

    @Test func wikiHopLockRejectsNativeAndExplicitNavigationRevealRequests() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.setNavigationColumnsVisible(false)
        appState.startWikiHop(
            mode: .chill,
            start: Article(id: "swift", title: "Swift"),
            target: Article(id: "objective-c", title: "Objective-C")
        )

        appState.toggleListsSidebarVisibility()
        appState.toggleDirectoryColumnVisibility()
        appState.navigationSplitViewVisibility = .all

        #expect(appState.workspaceNavigationColumns == .readerOnly)
    }

    @Test func readerPresentationRequestsRequireAnUnlockedArticle() {
        let appState = AppState(persistenceMode: .ephemeral)

        appState.requestReaderStylePresentation()
        appState.requestReaderPageViewsPresentation()

        #expect(appState.readerStylePresentationRequestID == nil)
        #expect(appState.readerPageViewsPresentationRequestID == nil)

        appState.openArticle(Article(id: "swift", title: "Swift"))
        appState.requestReaderStylePresentation()
        appState.requestReaderPageViewsPresentation()

        let unlockedStyleRequest = appState.readerStylePresentationRequestID
        let unlockedPageViewsRequest = appState.readerPageViewsPresentationRequestID
        #expect(unlockedStyleRequest != nil)
        #expect(unlockedPageViewsRequest != nil)

        appState.startWikiHop(
            mode: .chill,
            start: Article(id: "swift", title: "Swift"),
            target: Article(id: "objective-c", title: "Objective-C")
        )
        appState.requestReaderStylePresentation()
        appState.requestReaderPageViewsPresentation()

        #expect(appState.readerStylePresentationRequestID == unlockedStyleRequest)
        #expect(appState.readerPageViewsPresentationRequestID == unlockedPageViewsRequest)
    }

    @Test func dismissFindOnPageInvalidatesQueryResultsAndQueuesLegacyClearRequest() {
        let appState = AppState(persistenceMode: .ephemeral)
        let tabID = UUID()
        let staleRequest = AppState.FindOnPageRequest(
            requestID: UUID(),
            tabID: tabID,
            query: "stale",
            backwards: false
        )
        appState.showFindOnPage = true
        appState.findOnPageQuery = "needle"
        appState.findOnPageMatchFound = true
        appState.findOnPageMatchCount = 4
        appState.pendingFindOnPageRequest = staleRequest
        appState.currentFindOnPageRequestID = staleRequest.requestID

        appState.dismissFindOnPage(activeTabID: tabID, clearsWebSelection: true)

        #expect(appState.showFindOnPage == false)
        #expect(appState.findOnPageQuery.isEmpty)
        #expect(appState.findOnPageMatchFound == nil)
        #expect(appState.findOnPageMatchCount == nil)
        #expect(appState.pendingFindOnPageRequest?.tabID == tabID)
        #expect(appState.pendingFindOnPageRequest?.query == "")
        #expect(appState.currentFindOnPageRequestID == appState.pendingFindOnPageRequest?.requestID)
    }

    @Test func changingTabsDismissesFindAndTargetsTheOutgoingTabForSelectionClear() {
        let appState = AppState(persistenceMode: .ephemeral)
        let outgoingTabID = UUID()
        let incomingTabID = UUID()
        appState.showFindOnPage = true
        appState.findOnPageQuery = "architecture"
        appState.findOnPageMatchFound = true
        appState.findOnPageMatchCount = 3

        appState.resetFindOnPageForTabChange(
            from: outgoingTabID,
            to: incomingTabID
        )

        #expect(!appState.showFindOnPage)
        #expect(appState.findOnPageQuery.isEmpty)
        #expect(appState.findOnPageMatchFound == nil)
        #expect(appState.findOnPageMatchCount == nil)
        #expect(appState.pendingFindOnPageRequest?.tabID == outgoingTabID)
        #expect(appState.pendingFindOnPageRequest?.query.isEmpty == true)
    }

    @Test func unchangedTabPreservesFindPresentation() {
        let appState = AppState(persistenceMode: .ephemeral)
        let tabID = UUID()
        appState.showFindOnPage = true
        appState.findOnPageQuery = "reader"

        appState.resetFindOnPageForTabChange(from: tabID, to: tabID)

        #expect(appState.showFindOnPage)
        #expect(appState.findOnPageQuery == "reader")
        #expect(appState.pendingFindOnPageRequest == nil)
    }

    @Test func resetHighlightWorkflowClearsPendingTransitions() {
        let appState = AppState(persistenceMode: .ephemeral)
        let highlightID = UUID()
        let requestID = UUID()
        appState.pendingHighlightText = "important"
        appState.selectedHighlightId = highlightID.uuidString
        appState.currentTextSelection = TextSelectionData(
            text: "important",
            elementPath: "p:nth-child(1)",
            startOffset: 4,
            length: 9,
            contextBefore: "very ",
            contextAfter: " text",
            sectionTitle: "Intro",
            rect: CGRect(x: 1, y: 2, width: 3, height: 4)
        )
        appState.pendingImmediateHighlight = AppState.ImmediateHighlightRequest(
            id: requestID,
            cssColor: "#ffd60a"
        )
        appState.pendingHighlightRehydrate = AppState.HighlightRehydrateRequest(
            id: highlightID,
            text: "important",
            cssColor: "#ffd60a",
            contextBefore: "very ",
            contextAfter: " text"
        )
        appState.lastHighlightRehydrateResult = AppState.HighlightRehydrateResult(
            id: highlightID,
            success: false,
            timestamp: Date()
        )
        appState.isHighlightRehydrateInProgress = true
        appState.pendingHighlightArticleRefresh = AppState.HighlightArticleRefreshRequest(
            id: requestID,
            articleTitle: "Swift"
        )
        appState.isHighlightArticleRefreshInProgress = true
        appState.lastHighlightArticleRefreshResult = AppState.HighlightArticleRefreshResult(
            requestId: requestID,
            articleTitle: "Swift",
            success: true,
            timestamp: Date()
        )
        appState.pendingHighlightColorChange = AppState.HighlightColorChangeRequest(
            id: highlightID,
            cssColor: "#64d2ff"
        )
        appState.pendingHighlightScroll = highlightID
        appState.pendingHighlightNoteEditorRequest = AppState.HighlightNoteEditorRequest(
            requestID: requestID,
            highlightID: highlightID
        )
        appState.highlightTagFilterId = UUID()

        appState.resetHighlightWorkflowState()

        #expect(appState.pendingHighlightText == nil)
        #expect(appState.selectedHighlightId == nil)
        #expect(appState.currentTextSelection == nil)
        #expect(appState.pendingImmediateHighlight == nil)
        #expect(appState.pendingHighlightRehydrate == nil)
        #expect(appState.lastHighlightRehydrateResult == nil)
        #expect(appState.isHighlightRehydrateInProgress == false)
        #expect(appState.pendingHighlightArticleRefresh == nil)
        #expect(appState.isHighlightArticleRefreshInProgress == false)
        #expect(appState.lastHighlightArticleRefreshResult == nil)
        #expect(appState.pendingHighlightColorChange == nil)
        #expect(appState.pendingHighlightScroll == nil)
        #expect(appState.pendingHighlightNoteEditorRequest == nil)
        #expect(appState.highlightTagFilterId == nil)
    }

    @Test func wikiHopFeatureGateDisablesRuntimeSessionAndStartMode() {
        let defaults = UserDefaults.standard
        let keys = [
            AppStorageKey.Features.wikiHopPostV1Enabled,
            ExperimentFlag.wikiHopPOCEnabled.key,
            DiscoverStartMode.storageKey
        ]
        let previousValues = keys.reduce(into: [String: Any]()) { result, key in
            result[key] = defaults.object(forKey: key)
        }
        defer {
            for key in keys {
                if let value = previousValues[key] {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(false, forKey: AppStorageKey.Features.wikiHopPostV1Enabled)
        defaults.set(true, forKey: ExperimentFlag.wikiHopPOCEnabled.key)

        let appState = AppState(persistenceMode: .ephemeral)
        appState.startWikiHop(
            mode: .chill,
            start: Article(id: "start", title: "Start"),
            target: Article(id: "target", title: "Target")
        )
        defaults.set(DiscoverStartMode.wikiHop.rawValue, forKey: DiscoverStartMode.storageKey)

        appState.synchronizeExperimentStateFromDefaults()

        #expect(defaults.bool(forKey: ExperimentFlag.wikiHopPOCEnabled.key) == false)
        #expect(appState.wikiHopSession == nil)
        #expect(defaults.string(forKey: DiscoverStartMode.storageKey) == DiscoverStartMode.discoverFeed.rawValue)
    }

    @Test func appStateReadStateUpdatesRecentsAndQueuesTabSessionSave() {
        let appState = AppState(persistenceMode: .ephemeral)
        appState.recentArticles = [
            Article(id: "ada", title: "Ada Lovelace"),
            Article(id: "swift", title: "Swift")
        ]
        appState.openTabs = [
            ArticleTab(
                content: .history(
                    items: [
                        HistoryItem(article: Article(id: "ada-tab", title: "Ada_Lovelace"))
                    ],
                    currentIndex: 0
                )
            )
        ]

        let saveGeneration = appState.tabSessionStore.saveRequestGeneration
        appState.updateReadState(forTitle: "Ada Lovelace", isRead: true)

        #expect(appState.recentArticles[0].isRead == true)
        #expect(appState.recentArticles[1].isRead == false)
        #expect(appState.openTabs[0].history[0].article.isRead == true)
        #expect(appState.tabSessionStore.saveRequestGeneration == saveGeneration + 1)
        appState.saveTask?.cancel()
        appState.saveTask = nil
        appState.tabSessionStore.cancelPendingSaveForTesting()
    }
}
