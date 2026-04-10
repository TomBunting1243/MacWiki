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
}
