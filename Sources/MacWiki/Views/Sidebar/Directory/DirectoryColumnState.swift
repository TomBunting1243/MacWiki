import Foundation
import Observation

enum DirectoryColumnCommand: Equatable {
    case refreshDiscover
    case markSearchVisible(asRead: Bool)
    case saveSearchVisible(listID: UUID)
    case clearSelection
    case setSelectionLabel(labelID: UUID?)
    case addSelectionTag(tagID: UUID)
    case removeSelectionTag(tagID: UUID)
    case addSelectionToList(listID: UUID)
    case requestDeleteSelection
    case markVisible(asRead: Bool)
    case setUnreadFilter(isEnabled: Bool)
    case setSortMode(DirectorySupplementalSortMode)
}

struct DirectoryColumnCommandRequest: Identifiable, Equatable {
    let id = UUID()
    let command: DirectoryColumnCommand
}

/// Window-local state shared by the List Contents split item's content and
/// native top accessory. AppKit owns their geometry; both SwiftUI hosts observe
/// one selection/filter snapshot instead of mirroring pane chrome state.
@MainActor
@Observable
final class DirectoryColumnState {
    var localLabelFilter: Label?
    var localTagFilter: Tag?
    var supplementalReadFilter: DirectoryReadFilter = .all
    var supplementalSortMode: DirectorySupplementalSortMode = .recent
    var selectedSavedArticleIDs: Set<UUID> = []
    var selectionAnchorSavedArticleID: UUID?
    var showDeleteSelectedConfirmation = false
    var articleIndexesSnapshot = DirectoryArticleIndexes.empty
    var visibleSnapshot = DirectoryVisibleSnapshot.empty
    var visibleSnapshotScopeKey: String?
    var availableLists: [ReadingList] = []
    var availableLabels: [Label] = []
    var availableTags: [Tag] = []
    var commandRequest: DirectoryColumnCommandRequest?
    var isSearchFieldFocused = false

    func send(_ command: DirectoryColumnCommand) {
        commandRequest = DirectoryColumnCommandRequest(command: command)
    }
}
