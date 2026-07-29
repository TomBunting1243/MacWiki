import Foundation

/// Owns non-rendering directory-column work so task-token churn does not invalidate the
/// SwiftUI pane. The view still owns query inputs and pure snapshot construction.
@MainActor
final class DirectoryColumnCoordinator {
    static let defaultDiscoverLoadDelay: Duration = .milliseconds(170)

    private let saveScheduler: DebouncedActionScheduler
    private let sleep: @Sendable (Duration) async throws -> Void
    private var discoverDateLoadTask: Task<Void, Never>?

    init(
        saveDelay: Duration = .milliseconds(120),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        saveScheduler = DebouncedActionScheduler(delay: saveDelay)
        self.sleep = sleep
    }

    func refreshSnapshots(
        refreshArticleIndexes: @MainActor () -> Void,
        refreshVisibleSnapshot: @MainActor () -> Void
    ) async {
        await Task.yield()
        guard !Task.isCancelled else { return }
        refreshArticleIndexes()
        refreshVisibleSnapshot()
    }

    func scheduleSave(_ action: @escaping @MainActor () -> Void) {
        saveScheduler.schedule(action)
    }

    func flushSave(_ action: @escaping @MainActor () -> Void) {
        saveScheduler.flush(action)
    }

    func clearSavedArticleSelection(in state: DirectoryColumnState) {
        state.selectedSavedArticleIDs = []
        state.selectionAnchorSavedArticleID = nil
    }

    func resetSelectionScope(in state: DirectoryColumnState) {
        state.visibleSnapshotScopeKey = nil
        state.localLabelFilter = nil
        state.localTagFilter = nil
        clearSavedArticleSelection(in: state)
    }

    func queueDiscoverLoad(
        referenceDate: Date,
        forceRefresh: Bool = false,
        delay: Duration = DirectoryColumnCoordinator.defaultDiscoverLoadDelay,
        onForceRefresh: @MainActor () -> Void = {},
        queueLoad: @escaping @MainActor (Date, Bool) -> Void
    ) {
        cancelPendingDiscoverLoad()
        if forceRefresh {
            onForceRefresh()
        }

        let sleep = self.sleep
        discoverDateLoadTask = Task { @MainActor [weak self] in
            if !forceRefresh, delay > .zero {
                do {
                    try await sleep(delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.discoverDateLoadTask = nil
            queueLoad(referenceDate, forceRefresh)
        }
    }

    func handleRootSelectionChange(
        isDiscoverSelected: Bool,
        dismissPageViews: @MainActor () -> Void,
        cancelTrendLoad: @MainActor () -> Void
    ) {
        dismissPageViews()
        guard !isDiscoverSelected else { return }
        cancelPendingDiscoverLoad()
        cancelTrendLoad()
    }

    func handleDisappear(
        flushSave: @escaping @MainActor () -> Void,
        dismissPageViews: @MainActor () -> Void,
        cancelTrendLoad: @MainActor () -> Void,
        cancelMetadataHydration: @MainActor () -> Void
    ) {
        self.flushSave(flushSave)
        dismissPageViews()
        cancelPendingDiscoverLoad()
        cancelTrendLoad()
        cancelMetadataHydration()
    }

    func cancelPendingDiscoverLoad() {
        discoverDateLoadTask?.cancel()
        discoverDateLoadTask = nil
    }

    deinit {
        discoverDateLoadTask?.cancel()
    }
}
