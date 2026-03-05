import Foundation
import Observation

/// Loads and caches word-count metadata for Discover "Longest Reads" curation.
@Observable @MainActor
final class DiscoverWordCountStore {
    private(set) var wordCountByTitleKey: [String: Int] = [:]
    private(set) var isLoading = false

    private var loadTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(results: [WikipediaService.SearchResult]) {
        loadTask?.cancel()

        let targets = deduplicatedTargets(from: results)
        guard !targets.isEmpty else {
            wordCountByTitleKey.removeAll()
            isLoading = false
            return
        }

        let validKeys = Set(targets.map(\.key))
        wordCountByTitleKey = wordCountByTitleKey.filter { validKeys.contains($0.key) }
        isLoading = true

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(targets: targets)
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func wordCount(for title: String) -> Int? {
        wordCountByTitleKey[titleMatchKey(title)]
    }

    private func load(targets: [(title: String, key: String)]) async {
        await withTaskGroup(of: (String, Int?).self) { group in
            for target in targets {
                group.addTask { [wikipediaService] in
                    do {
                        let metadata = try await wikipediaService.fetchPageMetadata(target.title)
                        return (target.key, metadata.wordCount > 0 ? metadata.wordCount : nil)
                    } catch {
                        return (target.key, nil)
                    }
                }
            }

            for await (key, wordCount) in group {
                guard !Task.isCancelled else { return }
                guard let wordCount else { continue }
                wordCountByTitleKey[key] = wordCount
            }
        }

        guard !Task.isCancelled else { return }
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
}
