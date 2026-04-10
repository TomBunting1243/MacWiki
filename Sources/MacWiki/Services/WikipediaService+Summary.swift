import Foundation

extension WikipediaService {
    func fetchSummary(_ title: String) async throws -> ArticleSummary {
        let normalizedTitle = title.replacingOccurrences(of: " ", with: "_")

        // Check cache
        if let cached = cachedLRUValue(for: normalizedTitle, in: summaryCache, order: &summaryCacheOrder) {
            return cached
        }

        if let inFlight = inFlightSummaryTasks[normalizedTitle] {
            return try await inFlight.value
        }

        let task = Task<ArticleSummary, Error> { [self] in
            defer { clearInFlightSummaryTask(for: normalizedTitle) }

            guard let encodedTitle = normalizedTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                throw WikipediaError.invalidURL
            }

            guard let url = URL(string: "\(baseURL)/api/rest_v1/page/summary/\(encodedTitle)") else {
                throw WikipediaError.invalidURL
            }

            let data = try await performRequest(url: url)
            let summary = try parseSummary(data, title: title)

            storeLRUValue(
                summary,
                for: normalizedTitle,
                in: &summaryCache,
                order: &summaryCacheOrder,
                maxSize: maxSummaryCacheSize
            )

            return summary
        }
        inFlightSummaryTasks[normalizedTitle] = task

        return try await task.value
    }

    func parseSummary(_ data: Data, title: String) throws -> ArticleSummary {
        struct Response: Decodable {
            let pageid: Int
            let title: String
            let description: String?
            let extract: String?
            let thumbnail: Thumbnail?

            struct Thumbnail: Decodable {
                let source: String
                let width: Int?
                let height: Int?
            }
        }

        do {
            let response = try JSONDecoder().decode(Response.self, from: data)

            return ArticleSummary(
                title: response.title,
                description: response.description,
                extract: response.extract,
                thumbnailURL: response.thumbnail.flatMap { URL(string: $0.source) },
                thumbnailPixelSize: response.thumbnail.flatMap { thumbnail in
                    guard let width = thumbnail.width,
                          let height = thumbnail.height,
                          width > 0,
                          height > 0 else {
                        return nil
                    }
                    return CGSize(width: width, height: height)
                },
                pageId: response.pageid
            )
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }
}
