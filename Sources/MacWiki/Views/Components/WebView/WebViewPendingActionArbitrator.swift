import Foundation

/// Pure ordering policy for one-shot commands consumed by `WebView.updateNSView`.
///
/// The representable remains the owner of every `WKWebView` side effect. This
/// value only answers whether the current document may receive an action and
/// whether an action that already ran must defer the ordinary reload/sync path.
struct WebViewPendingActionArbitrator {
    enum DocumentState: Equatable {
        case unavailable
        case ready(matchesCurrentRevision: Bool)
    }

    enum ActionEffect: Equatable {
        /// State changed, but the current document was not touched.
        case stateOnly
        /// JavaScript, native find, or programmatic scrolling touched the document.
        case documentInteraction
    }

    enum FindAction: Equatable {
        case ignore
        case queueBehindInFlightRequest
        case deferUntilDocumentReady
        case clearSelection
        case execute
    }

    enum Continuation: Equatable {
        case stop
        case attemptHighlightRehydrate
        case continueDocumentUpdate
    }

    let documentState: DocumentState
    private(set) var didInteractWithDocument = false

    init(
        isContentLoadInFlight: Bool,
        canRunDocumentJavaScript: Bool,
        loadedDocumentMatchesCurrentRevision: Bool
    ) {
        if isContentLoadInFlight || !canRunDocumentJavaScript {
            documentState = .unavailable
        } else {
            documentState = .ready(
                matchesCurrentRevision: loadedDocumentMatchesCurrentRevision
            )
        }
    }

    var canPerformDocumentJavaScriptAction: Bool {
        if case .ready = documentState {
            return true
        }
        return false
    }

    var canPerformTableOfContentsScroll: Bool {
        documentState == .ready(matchesCurrentRevision: true)
    }

    var canAttemptHighlightRehydrate: Bool {
        canPerformDocumentJavaScriptAction
    }

    mutating func record(_ effect: ActionEffect) {
        if effect == .documentInteraction {
            didInteractWithDocument = true
        }
    }

    func findAction(
        pendingTabID: UUID,
        activeTabID: UUID,
        hasRequestInFlight: Bool,
        shouldDefer: Bool,
        trimmedQueryIsEmpty: Bool
    ) -> FindAction {
        guard pendingTabID == activeTabID else { return .ignore }
        if hasRequestInFlight {
            return .queueBehindInFlightRequest
        }
        if shouldDefer {
            return .deferUntilDocumentReady
        }
        return trimmedQueryIsEmpty ? .clearSelection : .execute
    }

    func continuation(hasPendingHighlightRehydrate: Bool) -> Continuation {
        if hasPendingHighlightRehydrate {
            return .attemptHighlightRehydrate
        }
        return didInteractWithDocument ? .stop : .continueDocumentUpdate
    }
}
