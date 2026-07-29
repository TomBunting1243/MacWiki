import Foundation
import Observation

struct DiscoverAllTimeMostReadLoadRequest: Equatable, Sendable {
    let limit: Int
    let referenceDate: Date
    let forceRefresh: Bool
    let fetchBudget: AllTimeMostReadFetchBudget
}

/// Loads and caches all-time most-read rankings for Discover collections.
@Observable @MainActor
final class DiscoverAllTimeMostReadStore {
    typealias RankingLoader = @Sendable (
        DiscoverAllTimeMostReadLoadRequest
    ) async throws -> [WikipediaService.AllTimeMostReadEntry]

    private(set) var entries: [WikipediaService.AllTimeMostReadEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadTask: Task<Void, Never>?
    @ObservationIgnored private let fetchBudget: AllTimeMostReadFetchBudget
    @ObservationIgnored private let rankingLoader: RankingLoader

    init(
        fetchBudget: AllTimeMostReadFetchBudget = .standard,
        rankingLoader: @escaping RankingLoader = { request in
            try await WikipediaService.shared.fetchAllTimeMostRead(
                limit: request.limit,
                referenceDate: request.referenceDate,
                forceRefresh: request.forceRefresh,
                fetchBudget: request.fetchBudget
            )
        }
    ) {
        self.fetchBudget = fetchBudget
        self.rankingLoader = rankingLoader
    }

    func queueLoad(
        limit: Int = 36,
        referenceDate: Date = Date(),
        forceRefresh: Bool = false
    ) {
        let clampedLimit = AllTimeMostReadCachePolicy.clampedLimit(limit)

        if !forceRefresh, !entries.isEmpty, entries.count >= clampedLimit {
            return
        }

        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(
                request: DiscoverAllTimeMostReadLoadRequest(
                    limit: clampedLimit,
                    referenceDate: referenceDate,
                    forceRefresh: forceRefresh,
                    fetchBudget: fetchBudget
                )
            )
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func load(request: DiscoverAllTimeMostReadLoadRequest) async {
        do {
            let ranked = try await rankingLoader(request)
            guard !Task.isCancelled else { return }
            entries = ranked
            isLoading = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            isLoading = false
            if entries.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}
