import Foundation
import Observation

/// Loads and caches today's most-read ranking for Discover.
@Observable @MainActor
final class DiscoverTodayMostReadStore {
    private(set) var results: [WikipediaService.SearchResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var currentRequestID: UUID?
    private var loadTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService
    private let autoRefreshIntervalNs: UInt64 = 5 * 60 * 1_000_000_000

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(forceRefresh: Bool = false) {
        loadTask?.cancel()
        configureAutoRefresh()
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(requestID: requestID, forceRefresh: forceRefresh)
        }
    }

    func cancel() {
        loadTask?.cancel()
        autoRefreshTask?.cancel()
        loadTask = nil
        autoRefreshTask = nil
        currentRequestID = nil
        isLoading = false
    }

    private func configureAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.autoRefreshIntervalNs)
                guard !Task.isCancelled else { return }
                self.queueLoad(forceRefresh: false)
            }
        }
    }

    private func load(requestID: UUID, forceRefresh: Bool) async {
        do {
            let trending = try await wikipediaService.fetchTrending(forceRefresh: forceRefresh)
            guard !Task.isCancelled else { return }
            guard currentRequestID == requestID else { return }
            results = trending
            isLoading = false
            errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            guard currentRequestID == requestID else { return }
            isLoading = false
            if results.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}
