import SwiftUI
import Testing

@testable import MacWiki

struct DiscoverCollectionsKeyboardCoordinatorTests {
    @Test func normalizedStateResetsWhenNoCollectionsAreVisible() {
        let state = DiscoverCollectionsKeyboardState(
            isActive: true,
            focusedLane: .longest,
            focusedMostReadRowIndex: 4,
            focusedLongestRowIndex: 7
        )

        let normalized = DiscoverCollectionsKeyboardCoordinator.normalized(
            state,
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 0, longestCount: 0)
        )

        #expect(normalized.isActive == false)
        #expect(normalized.focusedLane == .longest)
        #expect(normalized.focusedMostReadRowIndex == 0)
        #expect(normalized.focusedLongestRowIndex == 0)
    }

    @Test func markFocusActivatesAndClampsToVisibleRows() {
        let marked = DiscoverCollectionsKeyboardCoordinator.markedFocus(
            lane: .longest,
            index: 9,
            state: DiscoverCollectionsKeyboardState(),
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 3, longestCount: 2)
        )

        #expect(marked.isActive == true)
        #expect(marked.focusedLane == .longest)
        #expect(marked.focusedLongestRowIndex == 1)
    }

    @Test func moveUpActivatesKeyboardFocusAtLastVisibleRow() {
        let moved = DiscoverCollectionsKeyboardCoordinator.moved(
            DiscoverCollectionsKeyboardState(),
            direction: .up,
            isSearchFieldFocused: false,
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 5, longestCount: 2)
        )

        #expect(moved.isActive == true)
        #expect(moved.focusedLane == .mostRead)
        #expect(moved.focusedMostReadRowIndex == 4)
    }

    @Test func moveRightTransfersFocusAndClampsToTargetLane() {
        let state = DiscoverCollectionsKeyboardState(
            isActive: true,
            focusedLane: .mostRead,
            focusedMostReadRowIndex: 4,
            focusedLongestRowIndex: 0
        )

        let moved = DiscoverCollectionsKeyboardCoordinator.moved(
            state,
            direction: .right,
            isSearchFieldFocused: false,
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 6, longestCount: 2)
        )

        #expect(moved.focusedLane == .longest)
        #expect(moved.focusedLongestRowIndex == 1)
    }

    @Test func moveIsIgnoredWhileSearchFieldOwnsFocus() {
        let state = DiscoverCollectionsKeyboardState(
            isActive: true,
            focusedLane: .mostRead,
            focusedMostReadRowIndex: 1,
            focusedLongestRowIndex: 0
        )

        let moved = DiscoverCollectionsKeyboardCoordinator.moved(
            state,
            direction: .down,
            isSearchFieldFocused: true,
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 6, longestCount: 2)
        )

        #expect(moved == state)
    }

    @Test func focusedSelectionFallsBackToVisibleLaneDuringNormalization() {
        let selection = DiscoverCollectionsKeyboardCoordinator.focusedSelection(
            in: DiscoverCollectionsKeyboardState(
                isActive: true,
                focusedLane: .longest,
                focusedMostReadRowIndex: 3,
                focusedLongestRowIndex: 2
            ),
            context: DiscoverCollectionsKeyboardContext(mostReadCount: 4, longestCount: 0)
        )

        #expect(selection == .init(lane: .mostRead, index: 3))
    }
}
