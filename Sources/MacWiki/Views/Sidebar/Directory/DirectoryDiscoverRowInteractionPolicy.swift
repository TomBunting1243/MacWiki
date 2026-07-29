import Foundation

enum DirectoryDiscoverPrimaryTapDecision: Equatable, Sendable {
    case suppressPageViewsTap
    case openArticle
}

enum DirectoryDiscoverRowInteractionPolicy {
    static func rowKey(articleID: String, title: String) -> String {
        "discover:\(articleID):\(ReadStateSync.normalizedTitle(title))"
    }

    static func primaryTapDecision(
        rowKey: String,
        pendingPageViewsRowKey: String?
    ) -> DirectoryDiscoverPrimaryTapDecision {
        pendingPageViewsRowKey == rowKey ? .suppressPageViewsTap : .openArticle
    }

    static func shouldOpenInNewTab(
        explicitPreference: Bool?,
        isCommandPressed: Bool
    ) -> Bool {
        explicitPreference ?? isCommandPressed
    }

    static func toggledTagFilterID(
        currentTagID: UUID?,
        selectedTagID: UUID
    ) -> UUID? {
        currentTagID == selectedTagID ? nil : selectedTagID
    }

    static func pendingRowKeyAfterTimeout(
        currentPendingRowKey: String?,
        requestedRowKey: String
    ) -> String? {
        currentPendingRowKey == requestedRowKey ? nil : currentPendingRowKey
    }
}
