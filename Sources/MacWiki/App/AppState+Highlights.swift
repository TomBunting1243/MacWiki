import Foundation

extension AppState {
    func resetHighlightWorkflowState() {
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
    }
}

extension AppState.HighlightRehydrateRequest {
    init(highlight: Highlight) {
        self.init(
            id: highlight.id,
            text: highlight.text,
            cssColor: highlight.color.cssColor,
            contextBefore: highlight.contextBefore ?? "",
            contextAfter: highlight.contextAfter ?? ""
        )
    }
}
