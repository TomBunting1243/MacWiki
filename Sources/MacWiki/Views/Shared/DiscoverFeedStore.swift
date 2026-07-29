import Foundation
import Observation

struct DiscoverFeedThumbnailPrefetchBudget: Equatable, Sendable {
    static let initialViewport = DiscoverFeedThumbnailPrefetchBudget(
        maximumURLCount: 10,
        inTheNewsLimit: 4,
        trendingLimit: 4
    )

    let maximumURLCount: Int
    let inTheNewsLimit: Int
    let trendingLimit: Int

    init(maximumURLCount: Int, inTheNewsLimit: Int, trendingLimit: Int) {
        self.maximumURLCount = max(0, maximumURLCount)
        self.inTheNewsLimit = max(0, inTheNewsLimit)
        self.trendingLimit = max(0, trendingLimit)
    }
}

struct DiscoverFeedThumbnailPrefetchPlan: Equatable, Sendable {
    let urls: [URL]

    init(
        heroURL: URL?,
        featuredImageURL: URL?,
        inTheNewsURLs: [URL?],
        trendingURLs: [URL?],
        budget: DiscoverFeedThumbnailPrefetchBudget
    ) {
        var candidates: [URL] = []
        if let heroURL {
            candidates.append(heroURL)
        }
        if let featuredImageURL {
            candidates.append(featuredImageURL)
        }
        candidates.append(
            contentsOf: inTheNewsURLs.prefix(budget.inTheNewsLimit).compactMap { $0 }
        )
        candidates.append(
            contentsOf: trendingURLs.prefix(budget.trendingLimit).compactMap { $0 }
        )

        var seen = Set<URL>()
        urls = Array(
            candidates
                .filter { seen.insert($0).inserted }
                .prefix(budget.maximumURLCount)
        )
    }
}

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
        // Warm only the first useful viewport. Offscreen modules load their
        // own artwork as they become visible instead of competing with the
        // edition's initial text and lead image.
        let budget = DiscoverFeedThumbnailPrefetchBudget.initialViewport
        let plan = DiscoverFeedThumbnailPrefetchPlan(
            heroURL: feed.featuredArticle?.thumbnailURL,
            featuredImageURL: feed.featuredImage?.thumbnailURL ?? feed.featuredImage?.imageURL,
            inTheNewsURLs: feed.inTheNews.map(\.thumbnailURL),
            trendingURLs: feed.trending.map(\.thumbnailURL),
            budget: budget
        )
        guard !plan.urls.isEmpty else { return }
        Task(priority: .utility) {
            await ThumbnailPrefetcher.shared.prefetch(plan.urls)
        }
    }
}
