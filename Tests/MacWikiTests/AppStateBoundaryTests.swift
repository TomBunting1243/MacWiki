import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct AppStateBoundaryTests {
    @Test func dismissFindOnPageInvalidatesQueryResultsAndQueuesLegacyClearRequest() {
        let appState = AppState(loadPersistedState: false)
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

    @Test func resetHighlightWorkflowClearsPendingTransitions() {
        let appState = AppState(loadPersistedState: false)
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

        let appState = AppState(loadPersistedState: false)
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
}
