import Foundation

extension WikipediaService {
    func search(_ query: String) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        let cacheKey = trimmedQuery.lowercased()

        // Check cache
        if let cached = cachedLRUValue(for: cacheKey, in: searchCache, order: &searchCacheOrder) {
            return cached
        }

        // Build URL for Action API search
        var components = URLComponents(string: "\(baseURL)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "generator", value: "prefixsearch"),
            URLQueryItem(name: "gpssearch", value: trimmedQuery),
            URLQueryItem(name: "gpslimit", value: "10"),
            URLQueryItem(name: "prop", value: "pageimages|description"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            // Larger thumbnails keep search results crisp at the overlay's
            // expanded size without needing a second image fetch.
            URLQueryItem(name: "pithumbsize", value: "320"),
            URLQueryItem(name: "pilimit", value: "10"),
            URLQueryItem(name: "redirects", value: "1")
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url)
        let results = try parseSearchResults(data)

        // Cache results
        storeLRUValue(
            results,
            for: cacheKey,
            in: &searchCache,
            order: &searchCacheOrder,
            maxSize: maxSearchCacheSize
        )

        return results
    }

    func parseSearchResults(_ data: Data) throws -> [SearchResult] {
        struct Response: Decodable {
            let query: Query?

            struct Query: Decodable {
                let pages: [String: Page]?
            }

            struct Page: Decodable {
                let pageid: Int
                let title: String
                let description: String?
                let thumbnail: Thumbnail?
                let index: Int?

                struct Thumbnail: Decodable {
                    let source: String
                }
            }
        }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)

            guard let pages = response.query?.pages else {
                return []
            }

            // Sort by index to maintain search relevance order
            let sortedPages = pages.values.sorted { ($0.index ?? 0) < ($1.index ?? 0) }

            return sortedPages.map { page in
                SearchResult(
                    id: String(page.pageid),
                    title: page.title,
                    description: page.description,
                    thumbnailURL: page.thumbnail.flatMap { URL(string: $0.source) }
                )
            }
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }

    // MARK: - Trending

    /// Fetch the daily discovery feed used by New Tab and sidebar Discover.
    func fetchRandomArticles(count: Int) async throws -> [SearchResult] {
        guard count > 0 else { return [] }

        guard let randomURL = URL(string: "\(baseURL)/api/rest_v1/page/random/summary") else {
            throw WikipediaError.invalidURL
        }

        var results: [SearchResult] = []
        var seenTitles = Set<String>()
        let maxAttempts = max(12, count * 6)
        var attempts = 0

        while results.count < count && attempts < maxAttempts {
            attempts += 1

            let data = try await performRequest(url: randomURL)
            let summary = try parseSummary(data, title: "")
            let normalizedTitle = normalizedArticleTitle(summary.title).lowercased()

            guard !normalizedTitle.isEmpty,
                  normalizedTitle != "main_page",
                  !normalizedTitle.hasPrefix("special:"),
                  seenTitles.insert(normalizedTitle).inserted else {
                continue
            }

            results.append(
                SearchResult(
                    id: String(summary.pageId),
                    title: summary.title,
                    description: summary.description,
                    thumbnailURL: summary.thumbnailURL
                )
            )
        }

        guard results.count == count else {
            throw WikipediaError.noResults
        }

        return results
    }
}
