import Foundation
import Observation

/// Loads and caches trend pulse data for Discover's Most Read cards.
@Observable @MainActor
final class DiscoverTrendPulseStore {
    private(set) var pulseByTitleKey: [String: WikipediaService.TrendPulse] = [:]
    private(set) var isLoading = false

    private var currentRequestID: UUID?
    private var activeReferenceDateKey: String?
    private var loadTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(results: [WikipediaService.SearchResult], referenceDate: Date) {
        loadTask?.cancel()
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
        await withTaskGroup(of: (String, WikipediaService.TrendPulse?).self) { group in
            for target in targets {
                group.addTask { [wikipediaService] in
                    do {
                        let pulse = try await wikipediaService.fetchTrendPulse(
                            for: target.title,
                            referenceDate: referenceDate
                        )
                        return (target.key, pulse)
                    } catch {
                        return (target.key, nil)
                    }
                }
            }

            for await (key, pulse) in group {
                guard !Task.isCancelled else { return }
                guard currentRequestID == requestID else { return }
                guard activeReferenceDateKey == referenceDateKey else { return }
                guard let pulse else { continue }
                pulseByTitleKey[key] = pulse
            }
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

    private func titleMatchKey(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
