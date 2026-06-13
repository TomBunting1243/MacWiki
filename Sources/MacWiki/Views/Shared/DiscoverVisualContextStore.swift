import Foundation
import Observation

/// Loads media-list imagery used by Discover's "Visual Context" strip.
@Observable @MainActor
final class DiscoverVisualContextStore {
    private(set) var images: [WikipediaService.VisualContextImage] = []
    private(set) var isLoading = false

    private var currentTitleKey: String?
    private var loadTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(featuredTitle: String?) {
        loadTask?.cancel()

        guard
            let featuredTitle,
            !featuredTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            currentTitleKey = nil
            images = []
            isLoading = false
            return
        }

        let key = titleMatchKey(featuredTitle)
        guard !key.isEmpty else {
            currentTitleKey = nil
            images = []
            isLoading = false
            return
        }

        currentTitleKey = key
        isLoading = true
        images = []

        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(featuredTitle: featuredTitle, key: key)
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    private func load(featuredTitle: String, key: String) async {
        do {
            let loaded = try await wikipediaService.fetchVisualContextImages(for: featuredTitle, limit: 10)
            guard !Task.isCancelled else { return }
            guard currentTitleKey == key else { return }

            images = loaded
            isLoading = false

            let urls = loaded.map(\.thumbnailURL)
            if !urls.isEmpty {
                Task(priority: .utility) {
                    await ThumbnailPrefetcher.shared.prefetch(urls, maxConcurrent: 4)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            guard currentTitleKey == key else { return }
            images = []
            isLoading = false
        }
    }
}
