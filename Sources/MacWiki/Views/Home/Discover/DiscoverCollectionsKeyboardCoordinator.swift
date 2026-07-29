import SwiftUI

struct DiscoverCollectionsKeyboardState: Equatable {
    var isActive = false
    var focusedLane: DiscoverCollectionLane = .mostRead
    var focusedMostReadRowIndex = 0
    var focusedLongestRowIndex = 0
}

struct DiscoverCollectionsKeyboardContext: Equatable {
    var mostReadCount: Int
    var longestCount: Int

    var visibleLanes: [DiscoverCollectionLane] {
        var lanes: [DiscoverCollectionLane] = []
        if mostReadCount > 0 {
            lanes.append(.mostRead)
        }
        if longestCount > 0 {
            lanes.append(.longest)
        }
        return lanes
    }

    func rowCount(for lane: DiscoverCollectionLane) -> Int {
        switch lane {
        case .mostRead:
            mostReadCount
        case .longest:
            longestCount
        }
    }
}

enum DiscoverCollectionsKeyboardCoordinator {
    struct FocusedSelection: Equatable, Hashable {
        let lane: DiscoverCollectionLane
        let index: Int
    }

    static func focusedSelection(
        in state: DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) -> FocusedSelection? {
        let normalized = normalized(state, context: context)
        switch normalized.focusedLane {
        case .mostRead:
            guard context.mostReadCount > 0 else { return nil }
            return FocusedSelection(lane: .mostRead, index: normalized.focusedMostReadRowIndex)
        case .longest:
            guard context.longestCount > 0 else { return nil }
            return FocusedSelection(lane: .longest, index: normalized.focusedLongestRowIndex)
        }
    }

    static func focusedRowIndex(
        in state: DiscoverCollectionsKeyboardState,
        lane: DiscoverCollectionLane
    ) -> Int {
        switch lane {
        case .mostRead:
            state.focusedMostReadRowIndex
        case .longest:
            state.focusedLongestRowIndex
        }
    }

    static func isFocusedRow(
        lane: DiscoverCollectionLane,
        index: Int,
        state: DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) -> Bool {
        let normalized = normalized(state, context: context)
        guard normalized.isActive else { return false }
        guard normalized.focusedLane == lane else { return false }
        return focusedRowIndex(in: normalized, lane: lane) == index
    }

    static func markedFocus(
        lane: DiscoverCollectionLane,
        index: Int,
        state: DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) -> DiscoverCollectionsKeyboardState {
        var next = normalized(state, context: context)
        next.focusedLane = lane
        setFocusedRowIndex(index, for: lane, in: &next, context: context)
        next.isActive = true
        return next
    }

    static func normalized(
        _ state: DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) -> DiscoverCollectionsKeyboardState {
        var next = state
        let lanes = context.visibleLanes
        guard !lanes.isEmpty else {
            next.isActive = false
            next.focusedMostReadRowIndex = 0
            next.focusedLongestRowIndex = 0
            return next
        }

        if !lanes.contains(next.focusedLane) {
            next.focusedLane = lanes.contains(.mostRead) ? .mostRead : lanes[0]
        }

        setFocusedRowIndex(next.focusedMostReadRowIndex, for: .mostRead, in: &next, context: context)
        setFocusedRowIndex(next.focusedLongestRowIndex, for: .longest, in: &next, context: context)
        return next
    }

    static func moved(
        _ state: DiscoverCollectionsKeyboardState,
        direction: MoveCommandDirection,
        isSearchFieldFocused: Bool,
        context: DiscoverCollectionsKeyboardContext
    ) -> DiscoverCollectionsKeyboardState {
        guard !isSearchFieldFocused else { return state }

        var next = normalized(state, context: context)
        let lanes = context.visibleLanes
        guard !lanes.isEmpty else { return next }

        if !next.isActive {
            next.isActive = true
            if !lanes.contains(next.focusedLane) {
                next.focusedLane = lanes.contains(.mostRead) ? .mostRead : lanes[0]
            }
            if direction == .up {
                let lastRowIndex = max(context.rowCount(for: next.focusedLane) - 1, 0)
                setFocusedRowIndex(lastRowIndex, for: next.focusedLane, in: &next, context: context)
            } else if direction == .left || direction == .right {
                shiftFocusLane(direction, state: &next, context: context)
            }
            return next
        }

        switch direction {
        case .up:
            let nextIndex = max(focusedRowIndex(in: next, lane: next.focusedLane) - 1, 0)
            setFocusedRowIndex(nextIndex, for: next.focusedLane, in: &next, context: context)
        case .down:
            let maxIndex = max(context.rowCount(for: next.focusedLane) - 1, 0)
            let nextIndex = min(focusedRowIndex(in: next, lane: next.focusedLane) + 1, maxIndex)
            setFocusedRowIndex(nextIndex, for: next.focusedLane, in: &next, context: context)
        case .left, .right:
            shiftFocusLane(direction, state: &next, context: context)
        default:
            break
        }

        return next
    }

    static func deactivated(_ state: DiscoverCollectionsKeyboardState) -> DiscoverCollectionsKeyboardState {
        var next = state
        next.isActive = false
        return next
    }

    private static func shiftFocusLane(
        _ direction: MoveCommandDirection,
        state: inout DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) {
        let lanes = context.visibleLanes
        guard lanes.count > 1 else { return }
        guard let laneIndex = lanes.firstIndex(of: state.focusedLane) else {
            state.focusedLane = lanes[0]
            setFocusedRowIndex(0, for: lanes[0], in: &state, context: context)
            return
        }

        let targetLaneIndex: Int
        if direction == .left {
            targetLaneIndex = max(laneIndex - 1, 0)
        } else if direction == .right {
            targetLaneIndex = min(laneIndex + 1, lanes.count - 1)
        } else {
            return
        }

        guard targetLaneIndex != laneIndex else { return }
        let targetLane = lanes[targetLaneIndex]
        let sourceIndex = focusedRowIndex(in: state, lane: state.focusedLane)
        state.focusedLane = targetLane
        setFocusedRowIndex(sourceIndex, for: targetLane, in: &state, context: context)
    }

    private static func setFocusedRowIndex(
        _ index: Int,
        for lane: DiscoverCollectionLane,
        in state: inout DiscoverCollectionsKeyboardState,
        context: DiscoverCollectionsKeyboardContext
    ) {
        let upperBound = max(context.rowCount(for: lane) - 1, 0)
        let clamped = min(max(index, 0), upperBound)
        switch lane {
        case .mostRead:
            state.focusedMostReadRowIndex = clamped
        case .longest:
            state.focusedLongestRowIndex = clamped
        }
    }
}
