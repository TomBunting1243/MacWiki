import Foundation
import Observation

/// Loads and caches all-time most-read rankings for Discover collections.
@Observable @MainActor
final class DiscoverAllTimeMostReadStore {
    private(set) var entries: [WikipediaService.AllTimeMostReadEntry] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private var loadTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(limit: Int = 36, referenceDate: Date = Date()) {
        let clampedLimit = min(max(limit, 1), 80)

        if !entries.isEmpty && entries.count >= clampedLimit {
            return
        }

        loadTask?.cancel()
        isLoading = true
        errorMessage = nil

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(limit: clampedLimit, referenceDate: referenceDate)
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func load(limit: Int, referenceDate: Date) async {
        do {
            let ranked = try await wikipediaService.fetchAllTimeMostRead(
                limit: limit,
                referenceDate: referenceDate
            )
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
