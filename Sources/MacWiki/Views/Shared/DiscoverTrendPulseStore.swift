import Foundation
import Observation

/// Loads and caches trend pulse data for Discover's Most Read cards.
@Observable @MainActor
final class DiscoverTrendPulseStore {
    typealias TrendPulseLoader = @Sendable (
        _ title: String,
        _ referenceDate: Date
    ) async throws -> WikipediaService.TrendPulse

    private(set) var pulseByTitleKey: [String: WikipediaService.TrendPulse] = [:]
    private(set) var isLoading = false

    private var currentRequestID: UUID?
    private var activeReferenceDateKey: String?
    private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let trendPulseLoader: TrendPulseLoader
    @ObservationIgnored private let batchSize: Int
    @ObservationIgnored private(set) var batchPublicationCountForCurrentRequest = 0

    init(
        batchSize: Int = 6,
        trendPulseLoader: @escaping TrendPulseLoader = { title, referenceDate in
            try await WikipediaService.shared.fetchTrendPulse(
                for: title,
                referenceDate: referenceDate
            )
        }
    ) {
        self.batchSize = max(1, batchSize)
        self.trendPulseLoader = trendPulseLoader
    }

    func queueLoad(results: [WikipediaService.SearchResult], referenceDate: Date) {
        loadTask?.cancel()
        batchPublicationCountForCurrentRequest = 0
        let normalizedReferenceDate = Calendar.current.startOfDay(for: referenceDate)
        let referenceDateKey = referenceDateKey(for: normalizedReferenceDate)

        let targets = deduplicatedTargets(from: results)
        guard !targets.isEmpty else {
            pulseByTitleKey.removeAll()
            activeReferenceDateKey = referenceDateKey
            currentRequestID = nil
            isLoading = false
            return
        }

        if activeReferenceDateKey != referenceDateKey {
            pulseByTitleKey.removeAll()
            activeReferenceDateKey = referenceDateKey
        }

        let validKeys = Set(targets.map(\.key))
        pulseByTitleKey = pulseByTitleKey.filter { validKeys.contains($0.key) }
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(
                targets: targets,
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

    private func load(
        targets: [(title: String, key: String)],
        referenceDate: Date,
        referenceDateKey: String,
        requestID: UUID
    ) async {
        var batchStart = 0
        while batchStart < targets.count {
            guard !Task.isCancelled,
                  currentRequestID == requestID,
                  activeReferenceDateKey == referenceDateKey else {
                return
            }

            let batchEnd = min(batchStart + batchSize, targets.count)
            let batch = targets[batchStart..<batchEnd]

            let batchUpdates = await withTaskGroup(
                of: (String, WikipediaService.TrendPulse?).self,
                returning: [String: WikipediaService.TrendPulse].self
            ) { group in
                for target in batch {
                    group.addTask { [trendPulseLoader] in
                        do {
                            let pulse = try await trendPulseLoader(
                                target.title,
                                referenceDate
                            )
                            return (target.key, pulse)
                        } catch {
                            return (target.key, nil)
                        }
                    }
                }

                var updates: [String: WikipediaService.TrendPulse] = [:]
                for await (key, pulse) in group {
                    guard let pulse else { continue }
                    updates[key] = pulse
                }
                return updates
            }

            guard !Task.isCancelled else { return }
            guard currentRequestID == requestID else { return }
            guard activeReferenceDateKey == referenceDateKey else { return }

            if !batchUpdates.isEmpty {
                var publishedPulses = pulseByTitleKey
                publishedPulses.merge(batchUpdates) { _, new in new }
                pulseByTitleKey = publishedPulses
                batchPublicationCountForCurrentRequest += 1
            }

            batchStart = batchEnd
        }

        guard !Task.isCancelled else { return }
        guard currentRequestID == requestID else { return }
        guard activeReferenceDateKey == referenceDateKey else { return }
        isLoading = false
    }

    private func deduplicatedTargets(
        from results: [WikipediaService.SearchResult]
    ) -> [(title: String, key: String)] {
        var seen = Set<String>()
        var targets: [(title: String, key: String)] = []

        for result in results {
            let key = titleMatchKey(result.title)
            guard !key.isEmpty else { continue }
            guard seen.insert(key).inserted else { continue }

            targets.append((result.title, key))
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
