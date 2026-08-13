import Foundation
import Testing

@testable import MacWiki

struct WebViewPendingActionArbitratorTests {
    @Test func loadingDocumentRejectsJavaScriptAndContentsActions() {
        let arbitrator = makeArbitrator(
            isContentLoadInFlight: true,
            canRunDocumentJavaScript: true,
            loadedDocumentMatchesCurrentRevision: true
        )

        #expect(!arbitrator.canPerformDocumentJavaScriptAction)
        #expect(!arbitrator.canPerformTableOfContentsScroll)
        #expect(!arbitrator.canAttemptHighlightRehydrate)
    }

    @Test func documentWithoutJavaScriptBridgeRejectsDocumentActions() {
        let arbitrator = makeArbitrator(
            isContentLoadInFlight: false,
            canRunDocumentJavaScript: false,
            loadedDocumentMatchesCurrentRevision: true
        )

        #expect(!arbitrator.canPerformDocumentJavaScriptAction)
        #expect(!arbitrator.canPerformTableOfContentsScroll)
        #expect(!arbitrator.canAttemptHighlightRehydrate)
    }

    @Test func staleReadyDocumentAllowsExistingActionsButNotContentsNavigation() {
        let arbitrator = makeArbitrator(
            loadedDocumentMatchesCurrentRevision: false
        )

        #expect(arbitrator.canPerformDocumentJavaScriptAction)
        #expect(!arbitrator.canPerformTableOfContentsScroll)
        #expect(arbitrator.canAttemptHighlightRehydrate)
    }

    @Test func currentReadyDocumentAllowsEveryDocumentAction() {
        let arbitrator = makeArbitrator()

        #expect(arbitrator.canPerformDocumentJavaScriptAction)
        #expect(arbitrator.canPerformTableOfContentsScroll)
        #expect(arbitrator.canAttemptHighlightRehydrate)
    }

    @Test func findForAnotherTabIsIgnored() {
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.findAction(
                pendingTabID: UUID(),
                activeTabID: UUID(),
                hasRequestInFlight: false,
                shouldDefer: false,
                trimmedQueryIsEmpty: false
            ) == .ignore
        )
    }

    @Test func inFlightFindQueuesBeforeReadinessOrEmptyQueryDecisions() {
        let tabID = UUID()
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.findAction(
                pendingTabID: tabID,
                activeTabID: tabID,
                hasRequestInFlight: true,
                shouldDefer: true,
                trimmedQueryIsEmpty: true
            ) == .queueBehindInFlightRequest
        )
    }

    @Test func unstableDocumentLeavesFindPending() {
        let tabID = UUID()
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.findAction(
                pendingTabID: tabID,
                activeTabID: tabID,
                hasRequestInFlight: false,
                shouldDefer: true,
                trimmedQueryIsEmpty: false
            ) == .deferUntilDocumentReady
        )
    }

    @Test func stableEmptyFindClearsSelection() {
        let tabID = UUID()
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.findAction(
                pendingTabID: tabID,
                activeTabID: tabID,
                hasRequestInFlight: false,
                shouldDefer: false,
                trimmedQueryIsEmpty: true
            ) == .clearSelection
        )
    }

    @Test func stableNonemptyFindExecutes() {
        let tabID = UUID()
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.findAction(
                pendingTabID: tabID,
                activeTabID: tabID,
                hasRequestInFlight: false,
                shouldDefer: false,
                trimmedQueryIsEmpty: false
            ) == .execute
        )
    }

    @Test func queuedFindDoesNotBlockDocumentReloadOrSync() {
        var arbitrator = makeArbitrator()

        arbitrator.record(.stateOnly)

        #expect(
            arbitrator.continuation(hasPendingHighlightRehydrate: false)
                == .continueDocumentUpdate
        )
    }

    @Test func documentInteractionStopsOrdinaryUpdateWithoutRehydrate() {
        var arbitrator = makeArbitrator()

        arbitrator.record(.documentInteraction)

        #expect(
            arbitrator.continuation(hasPendingHighlightRehydrate: false) == .stop
        )
    }

    @Test func rehydrateTakesPriorityAfterAnotherDocumentAction() {
        var arbitrator = makeArbitrator()
        arbitrator.record(.documentInteraction)

        #expect(
            arbitrator.continuation(hasPendingHighlightRehydrate: true)
                == .attemptHighlightRehydrate
        )
    }

    @Test func rehydrateIsAttemptedWithoutAnotherPendingAction() {
        let arbitrator = makeArbitrator()

        #expect(
            arbitrator.continuation(hasPendingHighlightRehydrate: true)
                == .attemptHighlightRehydrate
        )
    }

    private func makeArbitrator(
        isContentLoadInFlight: Bool = false,
        canRunDocumentJavaScript: Bool = true,
        loadedDocumentMatchesCurrentRevision: Bool = true
    ) -> WebViewPendingActionArbitrator {
        WebViewPendingActionArbitrator(
            isContentLoadInFlight: isContentLoadInFlight,
            canRunDocumentJavaScript: canRunDocumentJavaScript,
            loadedDocumentMatchesCurrentRevision: loadedDocumentMatchesCurrentRevision
        )
    }
}
