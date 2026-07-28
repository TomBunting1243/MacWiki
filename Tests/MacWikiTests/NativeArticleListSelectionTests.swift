import Foundation
import Testing

@testable import MacWiki

struct NativeArticleListSelectionTests {
    private let first = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private let second = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    private let third = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3))
    private let fourth = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4))
    private let missing = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 99))

    @Test("selection scope chooses native multi-selection only for a selected reading list")
    func selectionScopeOwnsListAndRowPresentation() {
        let selectedList = SavedArticleSelectionPlanner.Scope.selectedReadingList
        #expect(selectedList.usesNativeListSelection)
        #expect(selectedList.allowsRangeSelection)
        #expect(selectedList.rowPresentation == .native)

        let otherContent = SavedArticleSelectionPlanner.Scope.otherDirectoryContent
        #expect(!otherContent.usesNativeListSelection)
        #expect(!otherContent.allowsRangeSelection)
        #expect(otherContent.rowPresentation == .custom)
    }

    @Test("all modifier combinations route native and custom row taps correctly", arguments: Array(UInt8(0)...UInt8(7)))
    func modifierRouting(rawModifiers: UInt8) {
        let modifiers = SavedArticleSelectionPlanner.Modifiers(rawValue: rawModifiers)
        let hasNativeSelectionModifier = modifiers.contains(.command) || modifiers.contains(.shift)
        let expectedNativeRouting: SavedArticleSelectionPlanner.PrimaryTapRouting =
            hasNativeSelectionModifier ? .deferToNativeListSelection : .performPrimaryAction

        #expect(SavedArticleSelectionPlanner.primaryTapRouting(
            presentation: .native,
            modifiers: modifiers
        ) == expectedNativeRouting)
        #expect(SavedArticleSelectionPlanner.primaryTapRouting(
            presentation: .custom,
            modifiers: modifiers
        ) == .performPrimaryAction)
    }

    @Test("all modifier combinations preserve selected-list primary-action behavior", arguments: Array(UInt8(0)...UInt8(7)))
    func selectedListPrimaryAction(rawModifiers: UInt8) {
        let modifiers = SavedArticleSelectionPlanner.Modifiers(rawValue: rawModifiers)
        let plan = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: third,
            orderedVisibleIDs: [first, second, third, fourth],
            currentAnchorID: first,
            scope: .selectedReadingList,
            modifiers: modifiers
        )

        if modifiers.contains(.shift) {
            #expect(plan.selectionUpdate == .init(
                selectedIDs: [first, second, third],
                anchorID: first
            ))
            #expect(plan.articleAction == .none)
        } else {
            #expect(plan.selectionUpdate == .init(
                selectedIDs: [third],
                anchorID: third
            ))
            let expectedAction: SavedArticleSelectionPlanner.ArticleAction = modifiers.contains(.option)
                ? .presentSavePrompt
                : .open(inNewTab: modifiers.contains(.command))
            #expect(plan.articleAction == expectedAction)
        }
    }

    @Test("other directory content never turns Shift into range selection", arguments: Array(UInt8(0)...UInt8(7)))
    func otherContentPrimaryAction(rawModifiers: UInt8) {
        let modifiers = SavedArticleSelectionPlanner.Modifiers(rawValue: rawModifiers)
        let plan = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: third,
            orderedVisibleIDs: [first, second, third, fourth],
            currentAnchorID: first,
            scope: .otherDirectoryContent,
            modifiers: modifiers
        )

        #expect(plan.selectionUpdate == .init(
            selectedIDs: [third],
            anchorID: third
        ))
        let expectedAction: SavedArticleSelectionPlanner.ArticleAction = modifiers.contains(.option)
            ? .presentSavePrompt
            : .open(inNewTab: modifiers.contains(.command))
        #expect(plan.articleAction == expectedAction)
    }

    @Test("Shift selects an inclusive range in either direction while retaining its anchor")
    func shiftRangeSelection() {
        let orderedIDs = [first, second, third, fourth]

        let forward = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: fourth,
            orderedVisibleIDs: orderedIDs,
            currentAnchorID: second,
            scope: .selectedReadingList,
            modifiers: [.shift]
        )
        #expect(forward.selectionUpdate == .init(
            selectedIDs: [second, third, fourth],
            anchorID: second
        ))
        #expect(forward.articleAction == .none)

        let reverse = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: second,
            orderedVisibleIDs: orderedIDs,
            currentAnchorID: fourth,
            scope: .selectedReadingList,
            modifiers: [.shift]
        )
        #expect(reverse.selectionUpdate == .init(
            selectedIDs: [second, third, fourth],
            anchorID: fourth
        ))
        #expect(reverse.articleAction == .none)
    }

    @Test("Shift starts a new one-row range when the anchor is empty or missing")
    func shiftRepairsEmptyOrMissingAnchor() {
        let orderedIDs = [first, second, third, fourth]
        let expected = SavedArticleSelectionPlanner.SelectionState(
            selectedIDs: [third],
            anchorID: third
        )

        let emptyAnchor = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: third,
            orderedVisibleIDs: orderedIDs,
            currentAnchorID: nil,
            scope: .selectedReadingList,
            modifiers: [.shift]
        )
        #expect(emptyAnchor.selectionUpdate == expected)
        #expect(emptyAnchor.articleAction == .none)

        let missingAnchor = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: third,
            orderedVisibleIDs: orderedIDs,
            currentAnchorID: missing,
            scope: .selectedReadingList,
            modifiers: [.shift]
        )
        #expect(missingAnchor.selectionUpdate == expected)
        #expect(missingAnchor.articleAction == .none)
    }

    @Test("Shift preserves state and does not open when the tapped row is absent")
    func shiftWithMissingTappedRow() {
        let missingFromVisibleRows = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: missing,
            orderedVisibleIDs: [first, second],
            currentAnchorID: first,
            scope: .selectedReadingList,
            modifiers: [.shift]
        )
        #expect(missingFromVisibleRows.selectionUpdate == nil)
        #expect(missingFromVisibleRows.articleAction == .none)

        let emptyRows = SavedArticleSelectionPlanner.planPrimaryAction(
            tappedID: missing,
            orderedVisibleIDs: [],
            currentAnchorID: nil,
            scope: .selectedReadingList,
            modifiers: [.shift, .command, .option]
        )
        #expect(emptyRows.selectionUpdate == nil)
        #expect(emptyRows.articleAction == .none)
    }

    @Test("anchor reconciliation follows native command-toggle selection changes")
    func anchorReconciliation() {
        let orderedIDs = [first, second, third, fourth]

        #expect(SavedArticleSelectionPlanner.anchorUpdate(
            currentAnchorID: second,
            selectedIDs: [second, fourth],
            orderedVisibleIDs: orderedIDs
        ) == .preserve)
        #expect(SavedArticleSelectionPlanner.anchorUpdate(
            currentAnchorID: second,
            selectedIDs: [first, third],
            orderedVisibleIDs: orderedIDs
        ) == .set(first))
        #expect(SavedArticleSelectionPlanner.anchorUpdate(
            currentAnchorID: nil,
            selectedIDs: [third, fourth],
            orderedVisibleIDs: orderedIDs
        ) == .set(third))
        #expect(SavedArticleSelectionPlanner.anchorUpdate(
            currentAnchorID: first,
            selectedIDs: [],
            orderedVisibleIDs: orderedIDs
        ) == .set(nil))
        #expect(SavedArticleSelectionPlanner.anchorUpdate(
            currentAnchorID: nil,
            selectedIDs: [missing],
            orderedVisibleIDs: orderedIDs
        ) == .set(nil))
    }

    @Test("custom selection chrome is drawn only for selected custom rows")
    func customSelectionChromePolicy() {
        #expect(ArticleListSelectionPresentation.custom.drawsCustomSelectionChrome(isSelected: true))
        #expect(!ArticleListSelectionPresentation.custom.drawsCustomSelectionChrome(isSelected: false))
        #expect(!ArticleListSelectionPresentation.native.drawsCustomSelectionChrome(isSelected: true))
        #expect(!ArticleListSelectionPresentation.native.drawsCustomSelectionChrome(isSelected: false))
    }

    @Test("saved article identifiers remain stable and distinct selection identities")
    func savedArticleIdentity() {
        let article = SavedArticle(title: "Ada Lovelace")
        let originalID = article.id
        article.title = "Augusta Ada King"

        #expect(article.id == originalID)
        #expect(SavedArticle(title: "Grace Hopper").id != originalID)
    }
}
