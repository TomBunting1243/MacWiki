import Foundation
import Observation
import SwiftData

struct ArticleMetadataHydrationSnapshot: Equatable, Sendable {
    var description: String?
    var extract: String?
    var thumbnailURL: URL?
    var wordCount: Int?

    mutating func merge(
        description: String?,
        extract: String?,
        thumbnailURL: URL?,
        wordCount: Int?
    ) {
        if let description {
            self.description = description
        }
        if let extract {
            self.extract = extract
        }
        if let thumbnailURL {
            self.thumbnailURL = thumbnailURL
        }
        if let wordCount {
            self.wordCount = wordCount
        }
    }
}

@MainActor
struct ArticleMetadataHydrationRequest {
    let title: String
    let articleID: String?
    let description: String?
    let extract: String?
    let thumbnailURL: URL?
    let wordCount: Int?
    let savedArticle: SavedArticle?

    init(
        title: String,
        articleID: String? = nil,
        description: String? = nil,
        extract: String? = nil,
        thumbnailURL: URL? = nil,
        wordCount: Int? = nil,
        savedArticle: SavedArticle? = nil
    ) {
        self.title = title
        self.articleID = articleID
        self.description = description
        self.extract = extract
        self.thumbnailURL = thumbnailURL
        self.wordCount = wordCount
        self.savedArticle = savedArticle
    }
}

@Observable @MainActor
final class ArticleMetadataHydrator {
    typealias SummaryLoader = @Sendable (String) async throws -> WikipediaService.ArticleSummary
    typealias PageMetadataLoader = @Sendable (String) async throws -> WikipediaService.PageMetadata

    private struct MergedRequest {
        let key: String
        var title: String
        var articleIDs: Set<String>
        var savedArticles: [SavedArticle]
        var snapshot: ArticleMetadataHydrationSnapshot
    }

    private struct LoadRequest: Sendable {
        let key: String
        let title: String
        let needsSummary: Bool
        let needsWordCount: Bool
    }

    private struct LoadResult: Sendable {
        let key: String
        let description: String?
        let extract: String?
        let thumbnailURL: URL?
        let wordCount: Int?
    }

    private(set) var snapshotByTitleKey: [String: ArticleMetadataHydrationSnapshot] = [:]

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var currentFingerprint: Int?
    @ObservationIgnored private let summaryLoader: SummaryLoader
    @ObservationIgnored private let pageMetadataLoader: PageMetadataLoader
    @ObservationIgnored private let batchSize: Int

    init(
        summaryLoader: @escaping SummaryLoader = { try await WikipediaService.shared.fetchSummary($0) },
        pageMetadataLoader: @escaping PageMetadataLoader = { try await WikipediaService.shared.fetchPageMetadata($0) },
        batchSize: Int = 6
    ) {
        self.summaryLoader = summaryLoader
        self.pageMetadataLoader = pageMetadataLoader
        self.batchSize = max(1, batchSize)
    }

    func snapshot(for title: String) -> ArticleMetadataHydrationSnapshot? {
        snapshotByTitleKey[Self.titleKey(for: title)]
    }

    func resolvedWordCount(for savedArticle: SavedArticle) -> Int {
        snapshot(for: savedArticle.title)?.wordCount ?? savedArticle.wordCount ?? savedArticle.approximateLength
    }

    func resolvedWordCount(for article: Article) -> Int {
        snapshot(for: article.title)?.wordCount ?? article.wordCount ?? 0
    }

    func queueLoad(
        requests: [ArticleMetadataHydrationRequest],
        appState: AppState,
        modelContext: ModelContext
    ) {
        let merged = mergedRequests(from: requests)

        for request in merged.values {
            seedSnapshot(from: request)
        }

        var didMutateModel = false
        for request in merged.values {
            let snapshot = snapshotByTitleKey[request.key]
            didMutateModel = applySnapshot(
                snapshot,
                to: request,
                appState: appState
            ) || didMutateModel
        }
        if didMutateModel {
            modelContext.saveReportingFailure(operation: #function)
        }

        let loadRequests = merged.values.compactMap { request -> LoadRequest? in
            let snapshot = snapshotByTitleKey[request.key] ?? ArticleMetadataHydrationSnapshot()
            let needsSummary =
                snapshot.description == nil ||
                snapshot.extract == nil ||
                snapshot.thumbnailURL == nil
            let needsWordCount = snapshot.wordCount == nil
            guard needsSummary || needsWordCount else { return nil }
            return LoadRequest(
                key: request.key,
                title: request.title,
                needsSummary: needsSummary,
                needsWordCount: needsWordCount
            )
        }

        let fingerprint = Self.loadFingerprint(for: loadRequests)
        guard fingerprint != currentFingerprint else { return }
        currentFingerprint = fingerprint

        loadTask?.cancel()
        guard !loadRequests.isEmpty else { return }

        loadTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.load(
                requests: loadRequests,
                mergedRequests: merged,
                appState: appState,
                modelContext: modelContext
            )
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        currentFingerprint = nil
    }

    private func load(
        requests: [LoadRequest],
        mergedRequests: [String: MergedRequest],
        appState: AppState,
        modelContext: ModelContext
    ) async {
        guard !requests.isEmpty else { return }
        let loadStartedAt = CFAbsoluteTimeGetCurrent()
        let batchCount = (requests.count + batchSize - 1) / batchSize
        let summaryRequestCount = requests.reduce(0) { $0 + ($1.needsSummary ? 1 : 0) }
        let metadataRequestCount = requests.reduce(0) { $0 + ($1.needsWordCount ? 1 : 0) }

        var batchStart = 0
        while batchStart < requests.count {
            guard !Task.isCancelled else { return }
            let batchEnd = min(batchStart + batchSize, requests.count)
            let batch = Array(requests[batchStart..<batchEnd])
            var didMutateModel = false

            await withTaskGroup(of: LoadResult.self) { group in
                for request in batch {
                    group.addTask { [summaryLoader, pageMetadataLoader] in
                        let summary: WikipediaService.ArticleSummary?
                        if request.needsSummary {
                            summary = try? await summaryLoader(request.title)
                        } else {
                            summary = nil
                        }

                        let metadata: WikipediaService.PageMetadata?
                        if request.needsWordCount {
                            metadata = try? await pageMetadataLoader(request.title)
                        } else {
                            metadata = nil
                        }

                        return LoadResult(
                            key: request.key,
                            description: summary?.description,
                            extract: summary?.extract,
                            thumbnailURL: summary?.thumbnailURL,
                            wordCount: metadata?.wordCount
                        )
                    }
                }

                for await result in group {
                    guard !Task.isCancelled else { return }
                    guard let mergedRequest = mergedRequests[result.key] else { continue }
                    mergeResult(result)
                    didMutateModel = applySnapshot(
                        snapshotByTitleKey[result.key],
                        to: mergedRequest,
                        appState: appState
                    ) || didMutateModel
                }
            }

            if didMutateModel {
                modelContext.saveReportingFailure(operation: #function)
            }

            batchStart = batchEnd
        }

        guard !Task.isCancelled else { return }
        PerformanceMetricsStore.shared.record(
            kind: .sidebarHydration,
            durationMs: (CFAbsoluteTimeGetCurrent() - loadStartedAt) * 1_000,
            detail: "titles=\(mergedRequests.count) loads=\(requests.count) batches=\(batchCount) summary=\(summaryRequestCount) metadata=\(metadataRequestCount)"
        )
    }

    private func mergeResult(_ result: LoadResult) {
        let description = Self.normalizedText(result.description)
        let extract = Self.normalizedText(result.extract)
        let wordCount = Self.normalizedWordCount(result.wordCount)

        var snapshot = snapshotByTitleKey[result.key] ?? ArticleMetadataHydrationSnapshot()
        snapshot.merge(
            description: description,
            extract: extract,
            thumbnailURL: result.thumbnailURL,
            wordCount: wordCount
        )
        snapshotByTitleKey[result.key] = snapshot
    }

    private func seedSnapshot(from request: MergedRequest) {
        var snapshot = snapshotByTitleKey[request.key] ?? ArticleMetadataHydrationSnapshot()
        snapshot.merge(
            description: request.snapshot.description,
            extract: request.snapshot.extract,
            thumbnailURL: request.snapshot.thumbnailURL,
            wordCount: request.snapshot.wordCount
        )
        snapshotByTitleKey[request.key] = snapshot
    }

    private func applySnapshot(
        _ snapshot: ArticleMetadataHydrationSnapshot?,
        to request: MergedRequest,
        appState: AppState
    ) -> Bool {
        guard let snapshot else { return false }

        if !request.articleIDs.isEmpty {
            appState.updateArticleMetadata(
                ids: request.articleIDs,
                description: snapshot.description,
                extract: snapshot.extract,
                wordCount: snapshot.wordCount
            )
        }

        var didMutateModel = false
        for savedArticle in request.savedArticles {
            if Self.shouldBackfill(savedArticle.articleDescription),
               let description = snapshot.description {
                savedArticle.articleDescription = description
                didMutateModel = true
            }

            if Self.shouldBackfill(savedArticle.extract),
               let extract = snapshot.extract {
                savedArticle.extract = extract
                didMutateModel = true
            }

            if savedArticle.thumbnailURLString == nil,
               let thumbnailURL = snapshot.thumbnailURL {
                savedArticle.thumbnailURLString = thumbnailURL.absoluteString
                didMutateModel = true
            }

            if savedArticle.wordCount == nil,
               let wordCount = snapshot.wordCount {
                savedArticle.wordCount = wordCount
                didMutateModel = true
            }
        }

        return didMutateModel
    }

    private func mergedRequests(
        from requests: [ArticleMetadataHydrationRequest]
    ) -> [String: MergedRequest] {
        var merged: [String: MergedRequest] = [:]

        for request in requests {
            let key = Self.titleKey(for: request.title)
            guard !key.isEmpty else { continue }

            var entry = merged[key] ?? MergedRequest(
                key: key,
                title: request.title,
                articleIDs: [],
                savedArticles: [],
                snapshot: ArticleMetadataHydrationSnapshot()
            )

            if let articleID = request.articleID {
                entry.articleIDs.insert(articleID)
            }

            if let savedArticle = request.savedArticle,
               !entry.savedArticles.contains(where: { $0.id == savedArticle.id }) {
                entry.savedArticles.append(savedArticle)
            }

            entry.snapshot.merge(
                description: Self.normalizedText(request.description),
                extract: Self.normalizedText(request.extract),
                thumbnailURL: request.thumbnailURL,
                wordCount: Self.normalizedWordCount(request.wordCount)
            )

            merged[key] = entry
        }

        return merged
    }

    private static func loadFingerprint(for requests: [LoadRequest]) -> Int {
        var hasher = Hasher()
        hasher.combine(requests.count)
        for request in requests {
            hasher.combine(request.key)
            hasher.combine(request.needsSummary)
            hasher.combine(request.needsWordCount)
        }
        return hasher.finalize()
    }

    private static func titleKey(for title: String) -> String {
        ReadStateSync.normalizedTitle(title)
    }

    private static func shouldBackfill(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedWordCount(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
