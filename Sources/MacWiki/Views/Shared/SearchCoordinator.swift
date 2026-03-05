import Foundation
import Observation
import os

/// Shared async search state owner for Quick Search, Sidebar Search, and Discover search surfaces.
@Observable @MainActor
final class SearchCoordinator {
    private static let logger = Logger(subsystem: "com.macwiki", category: "search-coordinator")
    static let defaultDebounceMilliseconds = 300

    var searchText: String = "" {
        didSet {
            guard searchText != oldValue else { return }
            selectedIndex = 0
            scheduleSearch()
        }
    }

    var searchResults: [WikipediaService.SearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var selectedIndex = 0

    var trendingArticles: [WikipediaService.SearchResult] = []
    var isTrendingLoading = false

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasInput: Bool {
        !trimmedSearchText.isEmpty
    }

    var hasQuery: Bool {
        trimmedSearchText.count >= minimumQueryLength
    }

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var trendingTask: Task<Void, Never>?
    @ObservationIgnored private var currentSearchRequestID: UUID?

    @ObservationIgnored private let wikipediaService: WikipediaService
    @ObservationIgnored private let debounceDuration: Duration
    @ObservationIgnored private let minimumQueryLength: Int
    @ObservationIgnored private let supportsTrending: Bool
    @ObservationIgnored private let searchPrefetchLimit: Int
    @ObservationIgnored private let trendingPrefetchLimit: Int

    init(
        wikipediaService: WikipediaService = .shared,
        debounceMilliseconds: Int = SearchCoordinator.defaultDebounceMilliseconds,
        minimumQueryLength: Int = 2,
        supportsTrending: Bool = false,
        searchPrefetchLimit: Int = 24,
        trendingPrefetchLimit: Int = 24
    ) {
        self.wikipediaService = wikipediaService
        self.debounceDuration = .milliseconds(debounceMilliseconds)
        self.minimumQueryLength = max(1, minimumQueryLength)
        self.supportsTrending = supportsTrending
        self.searchPrefetchLimit = max(1, searchPrefetchLimit)
        self.trendingPrefetchLimit = max(1, trendingPrefetchLimit)
    }

    deinit {
        searchTask?.cancel()
        trendingTask?.cancel()
    }

    func clearSearch() {
        searchTask?.cancel()
        searchTask = nil
        currentSearchRequestID = nil
        searchText = ""
        searchResults = []
        isLoading = false
        errorMessage = nil
        selectedIndex = 0
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        currentSearchRequestID = nil
        isLoading = false

        trendingTask?.cancel()
        trendingTask = nil
        isTrendingLoading = false
    }

    func loadTrendingIfNeeded() {
        guard supportsTrending else { return }
        guard trendingArticles.isEmpty else { return }
        guard !isTrendingLoading else { return }

        isTrendingLoading = true
        trendingTask?.cancel()
        trendingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let articles = try await wikipediaService.fetchTrending()
                guard !Task.isCancelled else { return }
                trendingArticles = articles
                isTrendingLoading = false
                if !hasQuery {
                    clampSelectedIndex(usingTrendingFallback: true)
                }
                prefetchThumbnails(for: articles, limit: trendingPrefetchLimit)
            } catch {
                guard !Task.isCancelled else { return }
                isTrendingLoading = false
                Self.logger.error("Failed to load trending: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func activeResults(usingTrendingFallback: Bool) -> [WikipediaService.SearchResult] {
        if hasQuery {
            return searchResults
        }
        return usingTrendingFallback ? trendingArticles : []
    }

    func selectedResult(usingTrendingFallback: Bool) -> WikipediaService.SearchResult? {
        let results = activeResults(usingTrendingFallback: usingTrendingFallback)
        guard !results.isEmpty else { return nil }
        let clamped = min(max(selectedIndex, 0), results.count - 1)
        return results[clamped]
    }

    func moveSelectionUp(usingTrendingFallback: Bool) {
        let count = activeResults(usingTrendingFallback: usingTrendingFallback).count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func moveSelectionDown(usingTrendingFallback: Bool) {
        let count = activeResults(usingTrendingFallback: usingTrendingFallback).count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(selectedIndex + 1, count - 1)
    }

    func clampSelectedIndex(usingTrendingFallback: Bool) {
        let count = activeResults(usingTrendingFallback: usingTrendingFallback).count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex, 0), count - 1)
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = trimmedSearchText
        guard query.count >= minimumQueryLength else {
            searchResults = []
            isLoading = false
            errorMessage = nil
            currentSearchRequestID = nil
            clampSelectedIndex(usingTrendingFallback: true)
            return
        }

        isLoading = true
        errorMessage = nil
        let requestID = UUID()
        currentSearchRequestID = requestID

        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }

            do {
                let results = try await wikipediaService.search(query)
                guard !Task.isCancelled else { return }
                guard currentSearchRequestID == requestID else { return }
                guard trimmedSearchText == query else { return }

                searchResults = results
                isLoading = false
                errorMessage = nil
                clampSelectedIndex(usingTrendingFallback: false)
                prefetchThumbnails(for: results, limit: searchPrefetchLimit)
            } catch {
                guard !Task.isCancelled else { return }
                guard currentSearchRequestID == requestID else { return }
                guard trimmedSearchText == query else { return }

                searchResults = []
                isLoading = false
                errorMessage = error.localizedDescription
                clampSelectedIndex(usingTrendingFallback: false)
            }
        }
    }

    private func prefetchThumbnails(for results: [WikipediaService.SearchResult], limit: Int) {
        let urls = results.prefix(limit).compactMap(\.thumbnailURL)
        guard !urls.isEmpty else { return }

        Task(priority: .utility) {
            await ThumbnailPrefetcher.shared.prefetch(Array(urls))
        }
    }
}
