import Foundation
import Observation

/// Shared discover-feed loading state for sidebar and new-tab surfaces.
@Observable @MainActor
final class DiscoverFeedStore {
    var feed: WikipediaService.DiscoverFeed?
    var isLoading = false
    var errorMessage: String?

    private var currentRequestID: UUID?
    private var loadTask: Task<Void, Never>?
    private var autoRefreshTask: Task<Void, Never>?
    private let wikipediaService: WikipediaService
    private let autoRefreshIntervalNs: UInt64 = 5 * 60 * 1_000_000_000

    init(wikipediaService: WikipediaService = .shared) {
        self.wikipediaService = wikipediaService
    }

    func queueLoad(referenceDate: Date, forceRefresh: Bool) {
        loadTask?.cancel()
        configureAutoRefresh(referenceDate: referenceDate)
        loadTask = Task { [weak self] in
            guard let self else { return }
            await self.load(referenceDate: referenceDate, forceRefresh: forceRefresh)
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

    private func configureAutoRefresh(referenceDate: Date) {
        autoRefreshTask?.cancel()
        guard Calendar.current.isDate(referenceDate, inSameDayAs: Date()) else {
            autoRefreshTask = nil
            return
        }
        autoRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.autoRefreshIntervalNs)
                guard !Task.isCancelled else { return }
                await self.load(referenceDate: Date(), forceRefresh: false)
            }
        }
    }

    private func load(referenceDate: Date, forceRefresh: Bool) async {
        let requestID = UUID()
        currentRequestID = requestID
        isLoading = true
        errorMessage = nil

        do {
            let fetchedFeed = try await wikipediaService.fetchDiscoverFeed(
                referenceDate: referenceDate,
                forceRefresh: forceRefresh
            )
            guard !Task.isCancelled else { return }
            prefetchThumbnails(for: fetchedFeed)
            guard currentRequestID == requestID else { return }
            feed = fetchedFeed
            isLoading = false
        } catch {
            guard !Task.isCancelled else { return }
            guard currentRequestID == requestID else { return }
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func prefetchThumbnails(for feed: WikipediaService.DiscoverFeed) {
        var urls: [URL] = []
        if let hero = feed.featuredArticle?.thumbnailURL {
            urls.append(hero)
        }
        if let featuredImageURL = feed.featuredImage?.thumbnailURL ?? feed.featuredImage?.imageURL {
            urls.append(featuredImageURL)
        }
        urls.append(contentsOf: feed.inTheNews.prefix(16).compactMap(\.thumbnailURL))
        urls.append(contentsOf: feed.trending.prefix(24).compactMap(\.thumbnailURL))
        guard !urls.isEmpty else { return }
        Task(priority: .utility) {
            await ThumbnailPrefetcher.shared.prefetch(urls)
        }
    }
}
