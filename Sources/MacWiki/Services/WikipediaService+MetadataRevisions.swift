import Foundation

extension WikipediaService {
    func fetchRevisionMetadataWithTimeout(_ title: String, timeout: Duration) async -> RevisionMetadata {
        await withTaskGroup(of: RevisionMetadata.self, returning: RevisionMetadata.self) { group in
            group.addTask {
                await self.fetchRevisionMetadata(title)
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return RevisionMetadata(lastEdited: nil, firstCreated: nil)
            }

            let result = await group.next() ?? RevisionMetadata(lastEdited: nil, firstCreated: nil)
            group.cancelAll()
            return result
        }
    }

    /// Lightweight, allocation-friendly approximate word counter for HTML bodies.
    func estimateWordCount(fromHTML html: String) -> Int {
        var inTag = false
        var inWord = false
        var count = 0

        for scalar in html.unicodeScalars {
            switch scalar.value {
            case 60: // <
                inTag = true
                if inWord {
                    count += 1
                    inWord = false
                }
            case 62: // >
                inTag = false
            default:
                if inTag { continue }
                if CharacterSet.alphanumerics.contains(scalar) {
                    inWord = true
                } else if inWord {
                    count += 1
                    inWord = false
                }
            }
        }

        if inWord {
            count += 1
        }
        return count
    }

    func estimateWordCount(fromPlainText text: String) -> Int {
        var inWord = false
        var count = 0

        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                inWord = true
                continue
            }

            if inWord {
                count += 1
                inWord = false
            }
        }

        if inWord {
            count += 1
        }
        return count
    }

    /// Fast-path counter for first paint. Large documents use sampled scanning to
    /// avoid full-string traversal in the critical load path.
    func estimateWordCountFastPath(fromHTML html: String, htmlByteCount: Int) -> Int {
        if htmlByteCount <= fastPathWordCountExactScanBytes {
            return estimateWordCount(fromHTML: html)
        }

        let sampleByteLimit = min(fastPathWordCountSampleBytes, htmlByteCount)
        var inTag = false
        var inWord = false
        var count = 0
        var scannedBytes = 0

        for scalar in html.unicodeScalars {
            scannedBytes += scalar.utf8.count
            if scannedBytes > sampleByteLimit {
                break
            }

            switch scalar.value {
            case 60: // <
                inTag = true
                if inWord {
                    count += 1
                    inWord = false
                }
            case 62: // >
                inTag = false
            default:
                if inTag { continue }
                if CharacterSet.alphanumerics.contains(scalar) {
                    inWord = true
                } else if inWord {
                    count += 1
                    inWord = false
                }
            }
        }

        if inWord {
            count += 1
        }

        let scale = Double(htmlByteCount) / Double(max(scannedBytes, 1))
        let estimated = Int((Double(count) * scale).rounded())
        return max(estimated, count)
    }

    func buildBaselineMetadata(wordCount: Int, lastEdited: Date?, firstCreated: Date?) -> [MetadataItem] {
        [
            MetadataItem(label: "Word count", value: formatWordCount(wordCount)),
            MetadataItem(label: "Last edited", value: formatMetadataDate(lastEdited)),
            MetadataItem(label: "First created", value: formatMetadataDate(firstCreated))
        ]
    }

    func formatWordCount(_ count: Int) -> String {
        let countString = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return count == 1 ? "\(countString) word" : "\(countString) words"
    }

    func formatMetadataDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    /// Article summary/preview
    // MARK: - Metadata (Word Count + Revisions)

    struct PageMetadata: Sendable {
        let wordCount: Int
    }

    struct RevisionMetadata: Sendable {
        let lastEdited: Date?
        let firstCreated: Date?
    }

    private enum RevisionDirection: String {
        case newer
        case older
    }

    static func clampedPageviewsWindowStart(
        requestedStart: Date,
        firstRevisionDate: Date?,
        datasetStart: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        var resolvedStart = calendar.startOfDay(for: requestedStart)

        if let datasetStart {
            let datasetFloor = calendar.startOfDay(for: datasetStart)
            if datasetFloor > resolvedStart {
                resolvedStart = datasetFloor
            }
        }

        if let firstRevisionDate {
            let firstRevisionDay = calendar.startOfDay(for: firstRevisionDate)
            if firstRevisionDay > resolvedStart {
                resolvedStart = firstRevisionDay
            }
        }

        return resolvedStart
    }

    /// Fetch lightweight metadata (word count) for an article
    func fetchPageMetadata(_ title: String) async throws -> PageMetadata {
        let normalizedTitle = normalizedArticleTitle(title)

        if let cached = cachedLRUValue(for: normalizedTitle, in: pageMetadataCache, order: &pageMetadataCacheOrder) {
            return cached
        }

        if let inFlight = inFlightPageMetadataTasks[normalizedTitle] {
            return try await inFlight.value
        }

        let task = Task<PageMetadata, Error> { [self] in
            defer { clearInFlightPageMetadataTask(for: normalizedTitle) }
            let metadata = try await fetchPageMetadataFromNetwork(title)
            storePageMetadata(metadata, for: normalizedTitle)
            return metadata
        }
        inFlightPageMetadataTasks[normalizedTitle] = task

        return try await task.value
    }

    func fetchPageMetadataFromNetwork(_ title: String) async throws -> PageMetadata {
        if let metadata = try await fetchPageMetadataFromSearch(title) {
            return metadata
        }

        return try await fetchPageMetadataFromExtract(title)
    }

    func fetchPageMetadataFromSearch(_ title: String) async throws -> PageMetadata? {
        var components = URLComponents(string: "\(baseURL)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: "intitle:\"\(title)\""),
            URLQueryItem(name: "srwhat", value: "text"),
            URLQueryItem(name: "srlimit", value: "10"),
            URLQueryItem(name: "srprop", value: "wordcount")
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url)

        struct SearchResponse: Decodable {
            let query: Query?
            struct Query: Decodable {
                let search: [SearchItem]
            }
            struct SearchItem: Decodable {
                let title: String
                let wordcount: Int?
            }
        }

        do {
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let candidates = response.query?.search, !candidates.isEmpty else {
                return nil
            }

            let targetTitleKey = normalizedTitleMatchKey(title)
            if let exact = candidates.first(where: { normalizedTitleMatchKey($0.title) == targetTitleKey }),
               let count = exact.wordcount,
               count > 0 {
                return PageMetadata(wordCount: count)
            }

            return nil
        } catch let error as WikipediaError {
            throw error
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }

    func fetchPageMetadataFromExtract(_ title: String) async throws -> PageMetadata {
        var components = URLComponents(string: "\(baseURL)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "extracts"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "explaintext", value: "1"),
            URLQueryItem(name: "exsectionformat", value: "plain")
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url)

        struct ExtractResponse: Decodable {
            let query: Query?

            struct Query: Decodable {
                let pages: [String: Page]
            }

            struct Page: Decodable {
                let title: String?
                let extract: String?
                let missing: String?
            }
        }

        do {
            let response = try JSONDecoder().decode(ExtractResponse.self, from: data)
            guard let pages = response.query?.pages.values else {
                throw WikipediaError.noResults
            }

            guard let page = pages.first(where: { $0.missing == nil }),
                  let extract = page.extract,
                  !extract.isEmpty else {
                throw WikipediaError.noResults
            }

            let wordCount = estimateWordCount(fromPlainText: extract)
            guard wordCount > 0 else {
                throw WikipediaError.noResults
            }

            return PageMetadata(wordCount: wordCount)
        } catch let error as WikipediaError {
            throw error
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }

    /// Fetch revision timestamps for last edited and first created dates
    func fetchRevisionMetadata(_ title: String) async -> RevisionMetadata {
        async let lastEditedResult = fetchRevisionTimestamp(title, direction: .older)
        async let firstCreatedResult = fetchRevisionTimestamp(title, direction: .newer)

        let lastEdited = try? await lastEditedResult
        let firstCreated = try? await firstCreatedResult

        return RevisionMetadata(lastEdited: lastEdited, firstCreated: firstCreated)
    }

    func resolvedPageviewsWindowStart(
        requestedStart: Date,
        title: String,
        datasetStart: Date? = nil
    ) async -> Date {
        let firstRevisionDate = await fetchFirstRevisionDate(title)
        return Self.clampedPageviewsWindowStart(
            requestedStart: requestedStart,
            firstRevisionDate: firstRevisionDate,
            datasetStart: datasetStart
        )
    }

    func fetchFirstRevisionDate(_ title: String) async -> Date? {
        let normalizedTitle = normalizedArticleTitle(title)
        guard !normalizedTitle.isEmpty else { return nil }

        if let cached = cachedLRUValue(
            for: normalizedTitle,
            in: firstRevisionDateCache,
            order: &firstRevisionDateCacheOrder
        ) {
            return cached
        }

        if let inFlight = inFlightFirstRevisionDateTasks[normalizedTitle] {
            return await inFlight.value
        }

        let task = Task<Date?, Never> { [self] in
            defer { clearInFlightFirstRevisionDateTask(for: normalizedTitle) }
            guard let firstRevisionDate = try? await fetchRevisionTimestamp(title, direction: .newer) else {
                return nil
            }
            storeLRUValue(
                firstRevisionDate,
                for: normalizedTitle,
                in: &firstRevisionDateCache,
                order: &firstRevisionDateCacheOrder,
                maxSize: maxFirstRevisionDateCacheSize
            )
            return firstRevisionDate
        }
        inFlightFirstRevisionDateTasks[normalizedTitle] = task

        return await task.value
    }

    private func fetchRevisionTimestamp(_ title: String, direction: RevisionDirection) async throws -> Date {
        var components = URLComponents(string: "\(baseURL)/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "prop", value: "revisions"),
            URLQueryItem(name: "titles", value: title),
            URLQueryItem(name: "redirects", value: "1"),
            URLQueryItem(name: "rvlimit", value: "1"),
            URLQueryItem(name: "rvprop", value: "timestamp"),
            URLQueryItem(name: "rvdir", value: direction.rawValue)
        ]

        guard let url = components.url else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url)

        struct RevisionResponse: Decodable {
            let query: Query

            struct Query: Decodable {
                let pages: [String: Page]
            }

            struct Page: Decodable {
                let revisions: [Revision]?
            }

            struct Revision: Decodable {
                let timestamp: String
            }
        }

        do {
            let response = try JSONDecoder().decode(RevisionResponse.self, from: data)
            guard let page = response.query.pages.values.first,
                  let timestamp = page.revisions?.first?.timestamp,
                  let date = parseRevisionTimestamp(timestamp) else {
                throw WikipediaError.noResults
            }
            return date
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }

    func parseRevisionTimestamp(_ timestamp: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: timestamp) {
            return date
        }
        return iso8601Formatter.date(from: timestamp)
    }

    func parsePageviewsTimestamp(_ timestamp: String) -> Date? {
        guard timestamp.count >= 8 else { return nil }
        let dayToken = String(timestamp.prefix(8))
        return pageviewsDateFormatter.date(from: dayToken)
    }

    // MARK: - Network
}
