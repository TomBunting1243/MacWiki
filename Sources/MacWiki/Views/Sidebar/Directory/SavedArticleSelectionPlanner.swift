import Foundation

/// Pure selection decisions shared by the saved-article row and directory.
///
/// A selected reading list uses macOS `List` selection for modified pointer
/// clicks. The explicit primary action remains responsible for ordinary opens
/// and for accessibility activations that arrive with modifiers held.
struct SavedArticleSelectionPlanner {
    enum Scope: Equatable {
        case selectedReadingList
        case otherDirectoryContent

        var usesNativeListSelection: Bool {
            self == .selectedReadingList
        }

        var allowsRangeSelection: Bool {
            usesNativeListSelection
        }

        var rowPresentation: ArticleListSelectionPresentation {
            usesNativeListSelection ? .native : .custom
        }
    }

    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: UInt8

        static let command = Self(rawValue: 1 << 0)
        static let shift = Self(rawValue: 1 << 1)
        static let option = Self(rawValue: 1 << 2)

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        init(
            isCommandPressed: Bool,
            isShiftPressed: Bool,
            isOptionPressed: Bool
        ) {
            var modifiers: Self = []
            if isCommandPressed {
                modifiers.insert(.command)
            }
            if isShiftPressed {
                modifiers.insert(.shift)
            }
            if isOptionPressed {
                modifiers.insert(.option)
            }
            self = modifiers
        }
    }

    enum PrimaryTapRouting: Equatable {
        case performPrimaryAction
        case deferToNativeListSelection
    }

    enum ArticleAction: Equatable {
        case none
        case open(inNewTab: Bool)
        case presentSavePrompt
    }

    struct SelectionState: Equatable {
        var selectedIDs: Set<UUID>
        var anchorID: UUID?
    }

    struct PrimaryActionPlan: Equatable {
        /// `nil` preserves both selection and anchor exactly as they are.
        var selectionUpdate: SelectionState?
        var articleAction: ArticleAction
    }

    enum AnchorUpdate: Equatable {
        case preserve
        case set(UUID?)
    }

    static func primaryTapRouting(
        presentation: ArticleListSelectionPresentation,
        modifiers: Modifiers
    ) -> PrimaryTapRouting {
        guard presentation == .native,
              modifiers.contains(.command) || modifiers.contains(.shift) else {
            return .performPrimaryAction
        }
        return .deferToNativeListSelection
    }

    static func planPrimaryAction(
        tappedID: UUID,
        orderedVisibleIDs: [UUID],
        currentAnchorID: UUID?,
        scope: Scope,
        modifiers: Modifiers
    ) -> PrimaryActionPlan {
        if scope.allowsRangeSelection, modifiers.contains(.shift) {
            return PrimaryActionPlan(
                selectionUpdate: rangeSelection(
                    tappedID: tappedID,
                    orderedVisibleIDs: orderedVisibleIDs,
                    currentAnchorID: currentAnchorID
                ),
                articleAction: .none
            )
        }

        let articleAction: ArticleAction = modifiers.contains(.option)
            ? .presentSavePrompt
            : .open(inNewTab: modifiers.contains(.command))

        return PrimaryActionPlan(
            selectionUpdate: SelectionState(
                selectedIDs: [tappedID],
                anchorID: tappedID
            ),
            articleAction: articleAction
        )
    }

    static func anchorUpdate(
        currentAnchorID: UUID?,
        selectedIDs: Set<UUID>,
        orderedVisibleIDs: [UUID]
    ) -> AnchorUpdate {
        guard !selectedIDs.isEmpty else { return .set(nil) }
        if let currentAnchorID, selectedIDs.contains(currentAnchorID) {
            return .preserve
        }
        return .set(orderedVisibleIDs.first(where: selectedIDs.contains))
    }

    private static func rangeSelection(
        tappedID: UUID,
        orderedVisibleIDs: [UUID],
        currentAnchorID: UUID?
    ) -> SelectionState? {
        guard let tappedIndex = orderedVisibleIDs.firstIndex(of: tappedID) else {
            return nil
        }

        guard let currentAnchorID,
              let anchorIndex = orderedVisibleIDs.firstIndex(of: currentAnchorID) else {
            return SelectionState(selectedIDs: [tappedID], anchorID: tappedID)
        }

        let lowerBound = min(anchorIndex, tappedIndex)
        let upperBound = max(anchorIndex, tappedIndex)
        return SelectionState(
            selectedIDs: Set(orderedVisibleIDs[lowerBound...upperBound]),
            anchorID: currentAnchorID
        )
    }
}

extension ArticleListSelectionPresentation {
    func drawsCustomSelectionChrome(isSelected: Bool) -> Bool {
        self == .custom && isSelected
    }
}
