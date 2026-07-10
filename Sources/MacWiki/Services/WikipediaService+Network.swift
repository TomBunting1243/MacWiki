import Foundation

extension WikipediaService {
    func performRequest(
        url: URL,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad
    ) async throws -> Data {
        let maxAttempts = 2
        for attempt in 0..<maxAttempts {
            var request = URLRequest(url: url)
            request.cachePolicy = cachePolicy
            request.timeoutInterval = attempt == 0 ? 12 : 18
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue(
                isMobileHTMLRequest(url) ? "text/html,application/xhtml+xml" : "application/json",
                forHTTPHeaderField: "Accept"
            )

            do {
                let (data, response) = try await requestLoader(request)

                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200..<300:
                        return data
                    case 429:
                        if attempt < maxAttempts - 1 {
                            try await retrySleeper(.milliseconds(350))
                            continue
                        }
                        throw WikipediaError.rateLimited
                    case 500..<600:
                        if attempt < maxAttempts - 1 {
                            try await retrySleeper(.milliseconds(260))
                            continue
                        }
                        throw WikipediaError.networkError(
                            NSError(domain: "WikipediaService", code: httpResponse.statusCode, userInfo: nil)
                        )
                    default:
                        throw WikipediaError.networkError(
                            NSError(domain: "WikipediaService", code: httpResponse.statusCode, userInfo: nil)
                        )
                    }
                }

                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as WikipediaError {
                throw error
            } catch let error as URLError {
                guard !Task.isCancelled, error.code != .cancelled else {
                    throw CancellationError()
                }
                if attempt < maxAttempts - 1 && shouldRetryNetworkError(error) {
                    try await retrySleeper(.milliseconds(220))
                    continue
                }
                throw WikipediaError.networkError(error)
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                throw WikipediaError.networkError(error)
            }
        }

        throw WikipediaError.noResults
    }

    func isMobileHTMLRequest(_ url: URL) -> Bool {
        url.path.contains("/api/rest_v1/page/mobile-html/")
    }

    func shouldRetryNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

}
