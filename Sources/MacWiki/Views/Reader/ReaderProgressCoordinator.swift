import Foundation
import SwiftData

@MainActor
struct ReaderProgressCoordinator {
    private(set) var latestReadingProgress: Double = 0

    private var lastPersistedReadingProgress: Double = 0
    private var lastReadingProgressPersistTimestamp: TimeInterval = 0
    private var restoredProgressBaseline: Double = 0
    private var initialRestoreRegressionGuardUntil: TimeInterval = 0

    mutating func bootstrapFromPersisted(
        _ persistedProgress: Double,
        articleTitle: String,
        appState: AppState,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        let clamped = min(max(persistedProgress, 0), 1)
        appState.setLiveReadingProgress(forTitle: articleTitle, progress: clamped)
        latestReadingProgress = clamped
        lastPersistedReadingProgress = clamped
        lastReadingProgressPersistTimestamp = now
        restoredProgressBaseline = clamped
        initialRestoreRegressionGuardUntil = clamped > 0.08 ? (now + 4.2) : 0
    }

    mutating func bootstrapWithoutPersistedState(
        articleTitle: String,
        appState: AppState,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        appState.setLiveReadingProgress(forTitle: articleTitle, progress: 0)
        latestReadingProgress = 0
        lastPersistedReadingProgress = 0
        lastReadingProgressPersistTimestamp = now
        restoredProgressBaseline = 0
        initialRestoreRegressionGuardUntil = 0
    }

    mutating func consumeTelemetry(
        _ progress: Double,
        for article: Article,
        in modelContext: ModelContext,
        appState: AppState,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) -> Double? {
        let clamped = min(max(progress, 0), 1)
        if shouldIgnoreEarlyRestoreRegression(
            candidateProgress: clamped,
            articleTitle: article.title,
            appState: appState,
            now: now
        ) {
            return nil
        }

        latestReadingProgress = clamped
        appState.setLiveReadingProgress(forTitle: article.title, progress: clamped)
        persist(progress: clamped, for: article, in: modelContext, force: false, now: now)
        return clamped
    }

    mutating func persistCurrentProgress(
        for article: Article,
        in modelContext: ModelContext,
        force: Bool = false,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        persist(progress: latestReadingProgress, for: article, in: modelContext, force: force, now: now)
    }

    mutating func persist(
        progress: Double,
        for article: Article,
        in modelContext: ModelContext,
        force: Bool = false,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        let clamped = min(max(progress, 0), 1)
        let progressDelta = abs(clamped - lastPersistedReadingProgress)
        let timeDelta = now - lastReadingProgressPersistTimestamp
        let crossedCompletion = clamped >= 0.995 && lastPersistedReadingProgress < 0.995
        let shouldPersist = force
            || crossedCompletion
            || progressDelta >= 0.03
            || (progressDelta >= 0.012 && timeDelta >= 3.2)

        guard shouldPersist else { return }

        let persisted = ReadStateSync.updateReadingProgress(clamped, for: article, in: modelContext)
        lastPersistedReadingProgress = persisted
        lastReadingProgressPersistTimestamp = now
    }

    mutating func markAsCompleted(
        for article: Article,
        in modelContext: ModelContext,
        appState: AppState,
        now: TimeInterval = Date().timeIntervalSinceReferenceDate
    ) {
        appState.setLiveReadingProgress(forTitle: article.title, progress: 1)
        latestReadingProgress = 1
        lastPersistedReadingProgress = 1
        lastReadingProgressPersistTimestamp = now
        restoredProgressBaseline = 1
        initialRestoreRegressionGuardUntil = 0
        _ = ReadStateSync.applyReadState(true, for: article, in: modelContext, appState: appState)
    }

    private mutating func shouldIgnoreEarlyRestoreRegression(
        candidateProgress: Double,
        articleTitle: String,
        appState: AppState,
        now: TimeInterval
    ) -> Bool {
        guard now < initialRestoreRegressionGuardUntil else { return false }

        let baseline = max(restoredProgressBaseline, lastPersistedReadingProgress)
        guard baseline > 0.10 else { return false }

        if candidateProgress >= max(0.10, baseline * 0.55) {
            initialRestoreRegressionGuardUntil = 0
            return false
        }

        let largeNearTopDrop = candidateProgress < 0.06 && (baseline - candidateProgress) > 0.22
        if largeNearTopDrop {
            // Keep list-side live progress stable until restore settles.
            appState.setLiveReadingProgress(forTitle: articleTitle, progress: baseline)
            return true
        }

        return false
    }
}
