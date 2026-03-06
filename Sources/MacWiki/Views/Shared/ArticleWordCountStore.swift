import Foundation
import Observation

/// Loads and caches word-count metadata for search and discover surfaces.
@Observable @MainActor
final class ArticleWordCountStore {
    typealias PageMetadataLoader = @Sendable (String) async throws -> WikipediaService.PageMetadata

    private struct LoadTarget: Sendable {
        let title: String
        let key: String
    }

    private(set) var wordCountByTitleKey: [String: Int] = [:]
    private(set) var isLoading = false

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var attemptedTitleKeys = Set<String>()
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private let pageMetadataLoader: PageMetadataLoader
    @ObservationIgnored private let batchSize: Int

    init(
        pageMetadataLoader: @escaping PageMetadataLoader = { try await WikipediaService.shared.fetchPageMetadata($0) },
        batchSize: Int = 6
    ) {
        self.pageMetadataLoader = pageMetadataLoader
        self.batchSize = max(1, batchSize)
    }

    func queueLoad(
        results: [WikipediaService.SearchResult],
        limit: Int? = nil,
        skippingTitles: Set<String> = []
    ) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()

        let targets = deduplicatedTargets(from: results)
        guard !targets.isEmpty else {
            wordCountByTitleKey.removeAll()
            attemptedTitleKeys.removeAll()
            isLoading = false
            return
        }

        let validKeys = Set(targets.map(\.key))
        wordCountByTitleKey = wordCountByTitleKey.filter { validKeys.contains($0.key) }
        attemptedTitleKeys.formIntersection(validKeys)

        let skippedKeys = Set(skippingTitles.map(Self.titleKey(for:))).intersection(validKeys)
        let maximumTargetCount = max(0, limit ?? Int.max)
        var loadTargets: [LoadTarget] = []
        loadTargets.reserveCapacity(min(targets.count, maximumTargetCount))

        for target in targets {
            guard !skippedKeys.contains(target.key) else { continue }
            guard self.wordCountByTitleKey[target.key] == nil else { continue }
            guard !self.attemptedTitleKeys.contains(target.key) else { continue }

            loadTargets.append(target)
            if loadTargets.count >= maximumTargetCount {
                break
            }
        }

        guard !loadTargets.isEmpty else {
            isLoading = false
            return
        }

        isLoading = true
        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.load(targets: loadTargets, generation: generation)
        }
    }

    func cancel() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    func wordCount(for title: String) -> Int? {
        wordCountByTitleKey[Self.titleKey(for: title)]
    }

    private func load(targets: [LoadTarget], generation: Int) async {
        guard !targets.isEmpty else {
            if generation == loadGeneration {
                isLoading = false
            }
            return
        }

        var batchStart = 0
        while batchStart < targets.count {
            guard !Task.isCancelled, generation == loadGeneration else { return }
            let batchEnd = min(batchStart + batchSize, targets.count)
            let batch = Array(targets[batchStart..<batchEnd])

            await withTaskGroup(of: (String, Int?).self) { group in
                for target in batch {
                    group.addTask { [pageMetadataLoader] in
                        do {
                            let metadata = try await pageMetadataLoader(target.title)
                            let resolvedWordCount = metadata.wordCount > 0 ? metadata.wordCount : nil
                            return (target.key, resolvedWordCount)
                        } catch {
                            return (target.key, nil)
                        }
                    }
                }

                for await (key, wordCount) in group {
                    guard !Task.isCancelled, generation == loadGeneration else { return }
                    attemptedTitleKeys.insert(key)
                    guard let wordCount else { continue }
                    wordCountByTitleKey[key] = wordCount
                }
            }

            batchStart = batchEnd
        }

        guard !Task.isCancelled, generation == loadGeneration else { return }
        isLoading = false
    }

    private func deduplicatedTargets(
        from results: [WikipediaService.SearchResult]
    ) -> [LoadTarget] {
        var seen = Set<String>()
        var targets: [LoadTarget] = []
        targets.reserveCapacity(results.count)

        for result in results {
            let key = Self.titleKey(for: result.title)
            guard !key.isEmpty else { continue }
            guard seen.insert(key).inserted else { continue }
            targets.append(LoadTarget(title: result.title, key: key))
        }

        return targets
    }

    static func titleKey(for title: String) -> String {
        ReadStateSync.normalizedTitle(title)
    }
}
