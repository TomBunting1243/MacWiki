import Foundation

enum ListsSidebarAreaDropOperation {
    case articleHover
    case directArticleDrop
    case collectionDrop
}

enum ListsSidebarAreaDropBehavior: Equatable {
    case noAction
    case expandAfterDelay(Duration)
    case reject
    case accept
}

enum ListsSidebarAreaArticleDropPolicy {
    static let expansionDelay: Duration = .milliseconds(300)

    static func behavior(
        for operation: ListsSidebarAreaDropOperation,
        isExpanded: Bool
    ) -> ListsSidebarAreaDropBehavior {
        switch operation {
        case .articleHover:
            return isExpanded ? .noAction : .expandAfterDelay(expansionDelay)
        case .directArticleDrop:
            return .reject
        case .collectionDrop:
            return .accept
        }
    }
}
