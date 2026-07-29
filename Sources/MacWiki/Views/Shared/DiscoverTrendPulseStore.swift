import Foundation
import Observation

struct DiscoverTrendPulseLoadBudget: Equatable, Sendable {
    static let standard = DiscoverTrendPulseLoadBudget(
        concurrentRequestLimit: 4,
        automaticRetryLimit: 8
    )

    let concurrentRequestLimit: Int
    let automaticRetryLimit: Int

    init(concurrentRequestLimit: Int, automaticRetryLimit: Int) {
        self.concurrentRequestLimit = max(1, concurrentRequestLimit)
        self.automaticRetryLimit = max(0, automaticRetryLimit)
    }
}

/// Loads and caches trend pulse data for the bounded set of visible Discover article rows.
@Observable @MainActor
final class DiscoverTrendPulseStore {
    private struct Target: Sendable {
        let title: String
        let key: String
    }

    private struct LoadResult: Sendable {
        let target: Target
        let pulse: WikipediaService.TrendPulse?
        let shouldRetry: Bool
    }

    typealias TrendPulseLoader = @Sendable (
        _ title: String,
        _ referenceDate: Date
    ) async throws -> WikipediaService.TrendPulse
    typealias RetrySleeper = @Sendable (_ duration: Duration) async throws -> Void

    private(set) var pulseByTitleKey: [String: WikipediaService.TrendPulse] = [:]
    private(set) var failedTitleKeys: Set<String> = []
    private(set) var isLoading = false

    private var currentRequestID: UUID?
    private var activeReferenceDateKey: String?
    private var activeRefreshGeneration: Int?
    private var attemptedTitleKeys: Set<String> = []
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let trendPulseLoader: TrendPulseLoader
    @ObservationIgnored private let retrySleeper: RetrySleeper
    @ObservationIgnored private let loadBudget: DiscoverTrendPulseLoadBudget
    @ObservationIgnored private let automaticRetryDelay: Duration
    @ObservationIgnored private(set) var batchPublicationCountForCurrentRequest = 0

    init(
        loadBudget: DiscoverTrendPulseLoadBudget = .standard,
        automaticRetryDelay: Duration = .milliseconds(450),
        retrySleeper: @escaping RetrySleeper = { duration in
            try await Task.sleep(for: duration)
        },
        trendPulseLoader: @escaping TrendPulseLoader = { title, referenceDate in
            try await WikipediaService.shared.fetchTrendPulse(
                for: title,
                referenceDate: referenceDate
            )
        }
    ) {
        self.loadBudget = loadBudget
        self.automaticRetryDelay = automaticRetryDelay
        self.retrySleeper = retrySleeper
        self.trendPulseLoader = trendPulseLoader
    }

    func queueLoad(
        results: [WikipediaService.SearchResult],
        referenceDate: Date,
        refreshGeneration: Int = 0
    ) {
        loadTask?.cancel()
        batchPublicationCountForCurrentRequest = 0
        let normalizedReferenceDate = Calendar.current.startOfDay(for: referenceDate)
        let referenceDateKey = referenceDateKey(for: normalizedReferenceDate)
        let isExplicitRefresh = activeRefreshGeneration.map { $0 != refreshGeneration } ?? false
        activeRefreshGeneration = refreshGeneration

        let targets = deduplicatedTargets(from: results)
        guard !targets.isEmpty else {
            pulseByTitleKey.removeAll()
            attemptedTitleKeys.removeAll()
            failedTitleKeys.removeAll()
            activeReferenceDateKey = referenceDateKey
            currentRequestID = nil
            isLoading = false
            return
        }

        if activeReferenceDateKey != referenceDateKey {
            pulseByTitleKey.removeAll()
            attemptedTitleKeys.removeAll()
            failedTitleKeys.removeAll()
            activeReferenceDateKey = referenceDateKey
        }

        let validKeys = Set(targets.map(\.key))
        pulseByTitleKey = pulseByTitleKey.filter { validKeys.contains($0.key) }
        attemptedTitleKeys.formIntersection(validKeys)
        failedTitleKeys.formIntersection(validKeys)
        let pendingTargets = targets.filter { target in
            isExplicitRefresh
                || (pulseByTitleKey[target.key] == nil && !attemptedTitleKeys.contains(target.key))
        }
        guard !pendingTargets.isEmpty else {
            currentRequestID = nil
            isLoading = false
            return
        }

        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(
                targets: pendingTargets,
                referenceDate: normalizedReferenceDate,
                referenceDateKey: referenceDateKey,
                requestID: requestID
            )
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        currentRequestID = nil
        isLoading = false
    }

    func pulse(for title: String) -> WikipediaService.TrendPulse? {
        pulseByTitleKey[titleMatchKey(title)]
    }

    func record(
        _ pulse: WikipediaService.TrendPulse,
        for title: String,
        referenceDate: Date
    ) {
        let referenceDateKey = referenceDateKey(
            for: Calendar.current.startOfDay(for: referenceDate)
        )
        guard activeReferenceDateKey == referenceDateKey else { return }
        let key = titleMatchKey(title)
        guard !key.isEmpty else { return }
        pulseByTitleKey[key] = pulse
        attemptedTitleKeys.insert(key)
        failedTitleKeys.remove(key)
    }

    private func load(
        targets: [Target],
        referenceDate: Date,
        referenceDateKey: String,
        requestID: UUID
    ) async {
        guard let retryableFailures = await loadBatches(
            targets,
            referenceDate: referenceDate,
            referenceDateKey: referenceDateKey,
            requestID: requestID
        ) else {
            return
        }

        let retryTargets = Array(retryableFailures.prefix(loadBudget.automaticRetryLimit))
        if !retryTargets.isEmpty {
            do {
                try await retrySleeper(automaticRetryDelay)
            } catch {
                if requestIsActive(requestID, referenceDateKey: referenceDateKey) {
                    isLoading = false
                }
                return
            }
            guard requestIsActive(requestID, referenceDateKey: referenceDateKey) else {
                return
            }
            _ = await loadBatches(
                retryTargets,
                referenceDate: referenceDate,
                referenceDateKey: referenceDateKey,
                requestID: requestID
            )
        }

        guard requestIsActive(requestID, referenceDateKey: referenceDateKey) else { return }
        isLoading = false
    }

    private func loadBatches(
        _ targets: [Target],
        referenceDate: Date,
        referenceDateKey: String,
        requestID: UUID
    ) async -> [Target]? {
        var batchStart = 0
        var retryableFailures: [Target] = []
        while batchStart < targets.count {
            guard requestIsActive(requestID, referenceDateKey: referenceDateKey) else {
                return nil
            }

            let batchEnd = min(batchStart + loadBudget.concurrentRequestLimit, targets.count)
            let batch = Array(targets[batchStart..<batchEnd])
            let results = await loadBatch(batch, referenceDate: referenceDate)

            guard requestIsActive(requestID, referenceDateKey: referenceDateKey) else {
                return nil
            }

            attemptedTitleKeys.formUnion(batch.map(\.key))
            let batchUpdates = Dictionary(
                uniqueKeysWithValues: results.compactMap { result in
                    result.pulse.map { (result.target.key, $0) }
                }
            )
            for result in results {
                if result.pulse != nil {
                    failedTitleKeys.remove(result.target.key)
                } else {
                    failedTitleKeys.insert(result.target.key)
                    if result.shouldRetry {
                        retryableFailures.append(result.target)
                    }
                }
            }

            if !batchUpdates.isEmpty {
                var publishedPulses = pulseByTitleKey
                publishedPulses.merge(batchUpdates) { _, new in new }
                pulseByTitleKey = publishedPulses
                batchPublicationCountForCurrentRequest += 1
            }

            batchStart = batchEnd
        }

        return retryableFailures
    }

    private func loadBatch(
        _ targets: [Target],
        referenceDate: Date
    ) async -> [LoadResult] {
        await withTaskGroup(of: LoadResult.self, returning: [LoadResult].self) { group in
            for target in targets {
                group.addTask { [trendPulseLoader] in
                    do {
                        return LoadResult(
                            target: target,
                            pulse: try await trendPulseLoader(target.title, referenceDate),
                            shouldRetry: false
                        )
                    } catch is CancellationError {
                        return LoadResult(target: target, pulse: nil, shouldRetry: false)
                    } catch {
                        return LoadResult(
                            target: target,
                            pulse: nil,
                            shouldRetry: Self.isTransient(error)
                        )
                    }
                }
            }

            var results: [LoadResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    private func requestIsActive(_ requestID: UUID, referenceDateKey: String) -> Bool {
        !Task.isCancelled
            && currentRequestID == requestID
            && activeReferenceDateKey == referenceDateKey
    }

    nonisolated private static func isTransient(_ error: Error) -> Bool {
        guard let wikipediaError = error as? WikipediaService.WikipediaError else {
            return true
        }
        switch wikipediaError {
        case .rateLimited, .networkError:
            return true
        case .invalidURL, .decodingError, .noResults:
            return false
        }
    }

    private func deduplicatedTargets(
        from results: [WikipediaService.SearchResult]
    ) -> [Target] {
        var seen = Set<String>()
        var targets: [Target] = []

        for result in results {
            let key = titleMatchKey(result.title)
            guard !key.isEmpty else { continue }
            guard seen.insert(key).inserted else { continue }

            targets.append(Target(title: result.title, key: key))
        }

        return targets
    }

    private func referenceDateKey(for referenceDate: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: referenceDate)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
