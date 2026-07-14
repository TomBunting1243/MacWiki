import SwiftUI

extension DiscoverFeedSections {
    func pageViewsRowKey(
        section: String,
        result: WikipediaService.SearchResult,
        index: Int? = nil
    ) -> String {
        let titleKey = ReadStateSync.normalizedTitle(result.title)
        if let index {
            return "\(section):\(index):\(result.id):\(titleKey)"
        }
        return "\(section):\(result.id):\(titleKey)"
    }

    func presentPageViewsPopover(
        for result: WikipediaService.SearchResult,
        rowKey: String,
        initialPulse: WikipediaService.TrendPulse? = nil
    ) {
        activePageViewsPopover = DiscoverPageViewsPopoverPayload(
            rowKey: rowKey,
            title: result.title,
            initialPulse: initialPulse,
            referenceDate: trendReferenceDate
        )
    }

    func pageViewsPopoverBinding(for rowKey: String) -> Binding<Bool> {
        Binding(
            get: { activePageViewsPopover?.rowKey == rowKey },
            set: { isPresented in
                guard !isPresented else { return }
                if activePageViewsPopover?.rowKey == rowKey {
                    activePageViewsPopover = nil
                }
            }
        )
    }

    @ViewBuilder
    func pageViewsPopover(for rowKey: String) -> some View {
        if let payload = activePageViewsPopover, payload.rowKey == rowKey {
            DiscoverPageViewsPopoverContent(
                title: payload.title,
                referenceDate: payload.referenceDate,
                initialPulse: payload.initialPulse
            )
        }
    }

    var focusedCollectionResult: WikipediaService.SearchResult? {
        guard let selection = DiscoverCollectionsKeyboardCoordinator.focusedSelection(
            in: currentCollectionsKeyboardState(),
            context: collectionsKeyboardContext
        ) else {
            return nil
        }

        switch selection.lane {
        case .mostRead:
            guard keyboardMostReadResults.indices.contains(selection.index) else { return nil }
            return keyboardMostReadResults[selection.index]
        case .longest:
            guard keyboardLongestResults.indices.contains(selection.index) else { return nil }
            return keyboardLongestResults[selection.index]
        }
    }

    func isFocusedCollectionRow(lane: DiscoverCollectionLane, index: Int) -> Bool {
        DiscoverCollectionsKeyboardCoordinator.isFocusedRow(
            lane: lane,
            index: index,
            state: currentCollectionsKeyboardState(),
            context: collectionsKeyboardContext
        )
    }

    func markCollectionsFocus(lane: DiscoverCollectionLane, index: Int) {
        setCollectionExpansion(lane, isExpanded: true)
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.markedFocus(
                lane: lane,
                index: index,
                state: currentCollectionsKeyboardState(),
                context: collectionsKeyboardContext
            )
        )
    }

    func collectionExpansionBinding(for lane: DiscoverCollectionLane) -> Binding<Bool> {
        Binding(
            get: {
                switch lane {
                case .mostRead:
                    return isMostReadCollectionExpanded
                case .longest:
                    return isLongestReadsCollectionExpanded
                }
            },
            set: { isExpanded in
                setCollectionExpansion(lane, isExpanded: isExpanded)
            }
        )
    }

    func setCollectionExpansion(_ lane: DiscoverCollectionLane, isExpanded: Bool) {
        switch lane {
        case .mostRead:
            isMostReadCollectionExpanded = isExpanded
        case .longest:
            isLongestReadsCollectionExpanded = isExpanded
        }

        if !isExpanded && isCollectionsKeyboardFocusActive && focusedCollectionLane == lane {
            applyCollectionsKeyboardState(
                DiscoverCollectionsKeyboardCoordinator.deactivated(currentCollectionsKeyboardState())
            )
        }
    }

    func normalizeCollectionsKeyboardFocus() {
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.normalized(
                currentCollectionsKeyboardState(),
                context: collectionsKeyboardContext
            )
        )
    }

    func moveCollectionsFocus(_ direction: MoveCommandDirection) {
        applyCollectionsKeyboardState(
            DiscoverCollectionsKeyboardCoordinator.moved(
                currentCollectionsKeyboardState(),
                direction: direction,
                isSearchFieldFocused: isSearchFieldFocused,
                context: collectionsKeyboardContext
            )
        )
    }

    func openFocusedCollectionItem(inNewTab: Bool) {
        guard let result = focusedCollectionResult else { return }
        onOpen(result, inNewTab)
    }

    func currentCollectionsKeyboardState() -> DiscoverCollectionsKeyboardState {
        DiscoverCollectionsKeyboardState(
            isActive: isCollectionsKeyboardFocusActive,
            focusedLane: focusedCollectionLane,
            focusedMostReadRowIndex: focusedMostReadRowIndex,
            focusedLongestRowIndex: focusedLongestRowIndex
        )
    }

    func applyCollectionsKeyboardState(_ state: DiscoverCollectionsKeyboardState) {
        isCollectionsKeyboardFocusActive = state.isActive
        focusedCollectionLane = state.focusedLane
        focusedMostReadRowIndex = state.focusedMostReadRowIndex
        focusedLongestRowIndex = state.focusedLongestRowIndex

        if state.isActive {
            switch state.focusedLane {
            case .mostRead:
                isMostReadCollectionExpanded = true
            case .longest:
                isLongestReadsCollectionExpanded = true
            }
        }
    }
}
