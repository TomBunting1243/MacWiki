import Foundation
import Testing

@testable import MacWiki

@MainActor
struct DirectoryColumnCoordinatorTests {
    @Test func scopeResetClearsOnlyScopeBoundPublicationAndSelectionState() {
        let coordinator = DirectoryColumnCoordinator()
        let state = DirectoryColumnState()
        let label = Label(name: "Research")
        let tag = Tag(name: "History")
        let selectedID = UUID()

        state.localLabelFilter = label
        state.localTagFilter = tag
        state.visibleSnapshotScopeKey = "list:old"
        state.selectedSavedArticleIDs = [selectedID]
        state.selectionAnchorSavedArticleID = selectedID
        state.supplementalReadFilter = .unread
        state.supplementalSortMode = .title

        coordinator.resetSelectionScope(in: state)

        #expect(state.localLabelFilter == nil)
        #expect(state.localTagFilter == nil)
        #expect(state.visibleSnapshotScopeKey == nil)
        #expect(state.selectedSavedArticleIDs.isEmpty)
        #expect(state.selectionAnchorSavedArticleID == nil)
        #expect(state.supplementalReadFilter == .unread)
        #expect(state.supplementalSortMode == .title)
    }

    @Test func snapshotRefreshPreservesIndexThenVisiblePublicationOrder() async {
        let coordinator = DirectoryColumnCoordinator()
        var events: [String] = []

        await coordinator.refreshSnapshots(
            refreshArticleIndexes: { events.append("indexes") },
            refreshVisibleSnapshot: { events.append("visible") }
        )

        #expect(events == ["indexes", "visible"])
    }

    @Test func cancelledSnapshotRefreshPublishesNothing() async {
        let coordinator = DirectoryColumnCoordinator()
        var events: [String] = []

        let task = Task { @MainActor in
            await coordinator.refreshSnapshots(
                refreshArticleIndexes: { events.append("indexes") },
                refreshVisibleSnapshot: { events.append("visible") }
            )
        }
        task.cancel()
        await task.value

        #expect(events.isEmpty)
    }

    @Test func leavingDiscoverCancelsPendingLoadAndDismissesTransientState() async {
        let coordinator = DirectoryColumnCoordinator()
        var loads: [(Date, Bool)] = []
        var dismissCount = 0
        var trendCancelCount = 0

        coordinator.queueDiscoverLoad(
            referenceDate: Date(timeIntervalSinceReferenceDate: 42),
            delay: .milliseconds(30),
            queueLoad: { loads.append(($0, $1)) }
        )
        coordinator.handleRootSelectionChange(
            isDiscoverSelected: false,
            dismissPageViews: { dismissCount += 1 },
            cancelTrendLoad: { trendCancelCount += 1 }
        )

        try? await Task.sleep(for: .milliseconds(70))

        #expect(loads.isEmpty)
        #expect(dismissCount == 1)
        #expect(trendCancelCount == 1)
    }

    @Test func stayingInDiscoverDismissesTransientStateWithoutCancellingTheEditionLoad() async {
        let coordinator = DirectoryColumnCoordinator()
        var loadCount = 0
        var dismissCount = 0
        var trendCancelCount = 0

        coordinator.queueDiscoverLoad(
            referenceDate: Date(timeIntervalSinceReferenceDate: 84),
            delay: .milliseconds(10),
            queueLoad: { _, _ in loadCount += 1 }
        )
        coordinator.handleRootSelectionChange(
            isDiscoverSelected: true,
            dismissPageViews: { dismissCount += 1 },
            cancelTrendLoad: { trendCancelCount += 1 }
        )

        await waitUntil { loadCount == 1 }

        #expect(loadCount == 1)
        #expect(dismissCount == 1)
        #expect(trendCancelCount == 0)
    }

    @Test func forceRefreshAdvancesGenerationAndQueuesTheCapturedDate() async {
        let coordinator = DirectoryColumnCoordinator()
        let targetDate = Date(timeIntervalSinceReferenceDate: 126)
        var refreshGeneration = 0
        var queuedDate: Date?
        var queuedForceRefresh = false

        coordinator.queueDiscoverLoad(
            referenceDate: targetDate,
            forceRefresh: true,
            delay: .seconds(1),
            onForceRefresh: { refreshGeneration += 1 },
            queueLoad: { date, forceRefresh in
                queuedDate = date
                queuedForceRefresh = forceRefresh
            }
        )

        #expect(refreshGeneration == 1)
        await waitUntil { queuedDate != nil }
        #expect(queuedDate == targetDate)
        #expect(queuedForceRefresh)
    }

    @Test func disappearFlushesSaveAndCancelsEveryDirectoryWorker() async {
        let coordinator = DirectoryColumnCoordinator(saveDelay: .seconds(1))
        var saveCount = 0
        var loadCount = 0
        var dismissCount = 0
        var trendCancelCount = 0
        var metadataCancelCount = 0

        coordinator.scheduleSave { saveCount += 100 }
        coordinator.queueDiscoverLoad(
            referenceDate: Date(),
            delay: .milliseconds(30),
            queueLoad: { _, _ in loadCount += 1 }
        )
        coordinator.handleDisappear(
            flushSave: { saveCount += 1 },
            dismissPageViews: { dismissCount += 1 },
            cancelTrendLoad: { trendCancelCount += 1 },
            cancelMetadataHydration: { metadataCancelCount += 1 }
        )

        try? await Task.sleep(for: .milliseconds(70))

        #expect(saveCount == 1)
        #expect(loadCount == 0)
        #expect(dismissCount == 1)
        #expect(trendCancelCount == 1)
        #expect(metadataCancelCount == 1)
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline && !condition() {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}
