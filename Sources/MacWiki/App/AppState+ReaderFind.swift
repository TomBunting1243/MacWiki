import Foundation

extension AppState {
    func presentFindOnPage() {
        showFindOnPage = true
        findOnPageMatchFound = nil
    }

    func clearFindOnPageResults() {
        findOnPageMatchFound = nil
        findOnPageMatchCount = nil
    }

    @discardableResult
    func issueFindOnPageRequest(tabID: UUID, query: String, backwards: Bool) -> FindOnPageRequest {
        let request = FindOnPageRequest(
            requestID: UUID(),
            tabID: tabID,
            query: query,
            backwards: backwards
        )
        pendingFindOnPageRequest = request
        return request
    }

    func dismissFindOnPage(activeTabID: UUID?, clearsWebSelection: Bool) {
        showFindOnPage = false
        findOnPageQuery = ""
        clearFindOnPageResults()

        guard clearsWebSelection, let activeTabID else {
            pendingFindOnPageRequest = nil
            currentFindOnPageRequestID = nil
            return
        }

        let clearRequest = issueFindOnPageRequest(
            tabID: activeTabID,
            query: "",
            backwards: false
        )
        currentFindOnPageRequestID = clearRequest.requestID
    }

    func resetFindOnPageState() {
        showFindOnPage = false
        findOnPageQuery = ""
        clearFindOnPageResults()
        pendingFindOnPageRequest = nil
        currentFindOnPageRequestID = nil
    }

    /// Find belongs to the article that created it. Closing the presentation
    /// and targeting the old tab with a clear request prevents query/results
    /// from appearing over the next tab while allowing a pooled old web view
    /// to clear its native selection when it next processes messages.
    func resetFindOnPageForTabChange(from oldTabID: UUID?, to newTabID: UUID?) {
        guard oldTabID != newTabID else { return }
        let hasFindState = showFindOnPage
            || !findOnPageQuery.isEmpty
            || pendingFindOnPageRequest != nil
            || currentFindOnPageRequestID != nil
        guard hasFindState else { return }
        dismissFindOnPage(
            activeTabID: oldTabID,
            clearsWebSelection: oldTabID != nil
        )
    }
}
