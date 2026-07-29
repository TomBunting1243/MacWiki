import Foundation

extension WikipediaService {
    func fetchDiscoverFeed(referenceDate: Date = Date(), forceRefresh: Bool = false) async throws -> DiscoverFeed {
        let calendar = Calendar.current
        let fallbackDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let candidates = [referenceDate, fallbackDate]
        let todayDateKey = featuredFeedDatePath(for: Date())

        var lastError: Error?

        for candidate in candidates {
            let dateKey = featuredFeedDatePath(for: candidate)

            if !forceRefresh, let cached = cachedLRUValue(for: dateKey, in: discoverCache, order: &discoverCacheOrder) {
                let shouldRefresh = shouldRefreshDiscoverCache(
                    cachedFeed: cached,
                    cachedAt: discoverCacheFetchedAt[dateKey],
                    dateKey: dateKey,
                    todayDateKey: todayDateKey
                )
                if !shouldRefresh {
                    return cached
                }
            }

            guard let url = URL(string: "\(baseURL)/api/rest_v1/feed/featured/\(dateKey)") else {
                throw WikipediaError.invalidURL
            }

            do {
                async let onThisDayCollections: OnThisDayCollections? = {
                    try? await fetchOnThisDayCollections(for: candidate)
                }()
                let data = try await performRequest(url: url)
                try Task.checkCancellation()
                var feed = try parseDiscoverFeed(data, dateKey: dateKey)
                if let collections = await onThisDayCollections {
                    feed = apply(onThisDayCollections: collections, to: feed)
                }
                try Task.checkCancellation()
                storeLRUPairedValue(
                    primary: feed,
                    secondary: Date(),
                    for: dateKey,
                    primaryCache: &discoverCache,
                    secondaryCache: &discoverCacheFetchedAt,
                    order: &discoverCacheOrder,
                    maxSize: maxDiscoverCacheSize
                )
                storeLRUValue(
                    feed.trending,
                    for: dateKey,
                    in: &trendingCache,
                    order: &trendingCacheOrder,
                    maxSize: maxTrendingCacheSize
                )
                return feed
            } catch {
                if error is CancellationError || Task.isCancelled {
                    throw CancellationError()
                }
                lastError = error
                continue
            }
        }

        if let lastError {
            throw lastError
        }
        throw WikipediaError.noResults
    }

    func shouldRefreshDiscoverCache(
        cachedFeed: DiscoverFeed,
        cachedAt: Date?,
        dateKey: String,
        todayDateKey: String
    ) -> Bool {
        guard dateKey == todayDateKey else { return false }
        if cachedFeed.trending.isEmpty { return true }
        guard let cachedAt else { return true }
        return Date().timeIntervalSince(cachedAt) >= discoverTodayCacheTTL
    }

    /// Fetch most-read trending articles.
    /// Reuses the richer discovery feed to keep all "today" surfaces in sync.
    func fetchTrending(forceRefresh: Bool = false) async throws -> [SearchResult] {
        let feed = try await fetchDiscoverFeed(referenceDate: Date(), forceRefresh: forceRefresh)
        return feed.trending
    }

    /// Fetch recent daily pageview momentum for an article.
    /// Used by Discover's "Trend Pulse" row affordance.
    func fetchTrendPulse(
        for title: String,
        referenceDate: Date = Date(),
        days: Int = 8
    ) async throws -> TrendPulse {
        let normalizedTitle = normalizedArticleTitle(title)
        guard !normalizedTitle.isEmpty else { throw WikipediaError.noResults }

        let clampedDays = min(max(days, 3), 5_000)
        let endDate = Calendar.current.startOfDay(for: referenceDate)
        let requestedStartDate = Calendar.current.date(byAdding: .day, value: -(clampedDays - 1), to: endDate) ?? endDate
        let endKey = pageviewsDateFormatter.string(from: endDate)
        let cacheKey = "\(normalizedTitle.lowercased())|\(endKey)|\(clampedDays)"

        if let cached = cachedLRUValue(for: cacheKey, in: trendPulseCache, order: &trendPulseCacheOrder) {
            return cached
        }

        let startDate = await resolvedPageviewsWindowStart(
            requestedStart: requestedStartDate,
            title: normalizedTitle
        )
        guard startDate <= endDate else {
            throw WikipediaError.noResults
        }

        let articlePath = normalizedTitle
        guard
            let encodedArticle = articlePath.addingPercentEncoding(withAllowedCharacters: urlPathAllowedNoSlash)
        else {
            throw WikipediaError.invalidURL
        }

        let startKey = pageviewsDateFormatter.string(from: startDate)
        guard let url = URL(
            string: "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/\(encodedArticle)/daily/\(startKey)/\(endKey)"
        ) else {
            throw WikipediaError.invalidURL
        }

        struct Response: Decodable {
            struct Item: Decodable {
                let timestamp: String
                let views: Int
            }
            let items: [Item]
        }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let datedItems = response.items
            .compactMap { item -> (date: Date, views: Int)? in
                guard item.views >= 0 else { return nil }
                guard let date = parsePageviewsTimestamp(item.timestamp) else { return nil }
                return (date: date, views: item.views)
            }
            .sorted { lhs, rhs in
                lhs.date < rhs.date
            }
        let points = datedItems.map(\.views)
        guard let latestViews = points.last else {
            throw WikipediaError.noResults
        }
        let resolvedWindowStart = datedItems.first?.date ?? startDate
        let resolvedWindowEnd = datedItems.last?.date ?? endDate

        let pulse = TrendPulse(
            points: points,
            latestViews: latestViews,
            previousViews: points.dropLast().last,
            windowStart: resolvedWindowStart,
            windowEnd: resolvedWindowEnd
        )
        storeLRUValue(
            pulse,
            for: cacheKey,
            in: &trendPulseCache,
            order: &trendPulseCacheOrder,
            maxSize: maxTrendPulseCacheSize
        )
        return pulse
    }

    /// Fetch gallery-capable article imagery for Discover's "Visual Context" strip.
    func fetchVisualContextImages(
        for title: String,
        limit: Int = 10
    ) async throws -> [VisualContextImage] {
        let normalizedTitle = normalizedArticleTitle(title)
        guard !normalizedTitle.isEmpty else { return [] }

        let clampedLimit = min(max(limit, 1), 16)
        let cacheKey = "\(normalizedTitle.lowercased())|\(clampedLimit)"
        if let cached = cachedLRUValue(for: cacheKey, in: visualContextCache, order: &visualContextCacheOrder) {
            return cached
        }

        guard
            let encodedTitle = normalizedTitle.addingPercentEncoding(withAllowedCharacters: urlPathAllowedNoSlash),
            let url = URL(string: "\(baseURL)/api/rest_v1/page/media-list/\(encodedTitle)")
        else {
            throw WikipediaError.invalidURL
        }

        struct Response: Decodable {
            struct Item: Decodable {
                struct Caption: Decodable {
                    let html: String?
                    let text: String?
                }
                struct Source: Decodable {
                    let src: String?
                    let scale: String?
                }

                let title: String?
                let leadImage: Bool?
                let sectionID: Int?
                let type: String?
                let showInGallery: Bool?
                let caption: Caption?
                let srcset: [Source]?

                enum CodingKeys: String, CodingKey {
                    case title
                    case leadImage
                    case sectionID = "section_id"
                    case type
                    case showInGallery
                    case caption
                    case srcset
                }
            }

            let items: [Item]
        }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(Response.self, from: data)
        var seenTitles = Set<String>()

        let images = response.items
            .filter { item in
                item.type == "image" && (item.showInGallery ?? true)
            }
            .sorted { lhs, rhs in
                if (lhs.leadImage ?? false) != (rhs.leadImage ?? false) {
                    return (lhs.leadImage ?? false) && !(rhs.leadImage ?? false)
                }
                return (lhs.sectionID ?? Int.max) < (rhs.sectionID ?? Int.max)
            }
            .compactMap { item -> VisualContextImage? in
                guard let rawTitle = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !rawTitle.isEmpty else {
                    return nil
                }
                let key = rawTitle.lowercased()
                guard seenTitles.insert(key).inserted else {
                    return nil
                }

                let bestSource = item.srcset?
                    .sorted { lhs, rhs in
                        let leftScale = Double(lhs.scale?.replacingOccurrences(of: "x", with: "") ?? "") ?? 0
                        let rightScale = Double(rhs.scale?.replacingOccurrences(of: "x", with: "") ?? "") ?? 0
                        return leftScale > rightScale
                    }
                    .first?.src

                guard let source = bestSource, let thumbnailURL = normalizedMediaURL(source) else {
                    return nil
                }

                return VisualContextImage(
                    id: rawTitle,
                    mediaTitle: rawTitle,
                    caption: cleanedMetadataText(item.caption?.text ?? item.caption?.html),
                    thumbnailURL: thumbnailURL,
                    filePageURL: commonsFilePageURL(for: rawTitle)
                )
            }
            .prefix(clampedLimit)

        let result = Array(images)
        storeLRUValue(
            result,
            for: cacheKey,
            in: &visualContextCache,
            order: &visualContextCacheOrder,
            maxSize: maxVisualContextCacheSize
        )
        return result
    }

    /// Fetch top pageview days over the full available history window.
    /// Used by Trend Pulse popovers as historical context.
    func fetchPeakPageviewDays(
        for title: String,
        endingAt referenceDate: Date = Date(),
        top: Int = 5
    ) async throws -> [PeakPageviewDay] {
        let normalizedTitle = normalizedArticleTitle(title)
        guard !normalizedTitle.isEmpty else { return [] }

        let clampedTop = min(max(top, 1), 10)
        let endDate = Calendar.current.startOfDay(for: referenceDate)
        let endKey = pageviewsDateFormatter.string(from: endDate)
        let cacheKey = "\(normalizedTitle.lowercased())|\(endKey)|\(clampedTop)"

        if let cached = cachedLRUValue(for: cacheKey, in: peakPageviewDaysCache, order: &peakPageviewDaysCacheOrder) {
            return cached
        }

        // Wikimedia pageview dataset starts at 2015-07-01 for this endpoint.
        guard let historyStart = pageviewsDateFormatter.date(from: "20150701") else {
            return []
        }
        let startDate = await resolvedPageviewsWindowStart(
            requestedStart: historyStart,
            title: normalizedTitle,
            datasetStart: historyStart
        )
        if endDate < startDate {
            return []
        }

        let articlePath = normalizedTitle
        guard
            let encodedArticle = articlePath.addingPercentEncoding(withAllowedCharacters: urlPathAllowedNoSlash)
        else {
            throw WikipediaError.invalidURL
        }

        let startKey = pageviewsDateFormatter.string(from: startDate)
        guard let url = URL(
            string: "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/\(encodedArticle)/daily/\(startKey)/\(endKey)"
        ) else {
            throw WikipediaError.invalidURL
        }

        struct Response: Decodable {
            struct Item: Decodable {
                let timestamp: String
                let views: Int
            }
            let items: [Item]
        }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(Response.self, from: data)

        let peaks = response.items
            .compactMap { item -> PeakPageviewDay? in
                guard item.views >= 0 else { return nil }
                guard let date = parsePageviewsTimestamp(item.timestamp) else { return nil }
                return PeakPageviewDay(date: date, views: item.views)
            }
            .sorted { lhs, rhs in
                if lhs.views == rhs.views {
                    return lhs.date > rhs.date
                }
                return lhs.views > rhs.views
            }
            .prefix(clampedTop)

        let result = Array(peaks)
        storeLRUValue(
            result,
            for: cacheKey,
            in: &peakPageviewDaysCache,
            order: &peakPageviewDaysCacheOrder,
            maxSize: maxPeakPageviewCacheSize
        )
        return result
    }

    /// Fetch all-time most-read articles using aggregated monthly top pageview charts.
    /// "All-time" here maps to the full available Wikimedia pageviews history (since 2015-07).
    func fetchAllTimeMostRead(
        limit: Int = 36,
        referenceDate: Date = Date(),
        forceRefresh: Bool = false,
        fetchBudget: AllTimeMostReadFetchBudget = .standard
    ) async throws -> [AllTimeMostReadEntry] {
        let clampedLimit = AllTimeMostReadCachePolicy.clampedLimit(limit)
        guard let latestMonth = latestCompletedTopPageviewsMonth(endingAt: referenceDate) else {
            return []
        }

        let cacheKey = "all-time-\(latestMonth.year)-\(latestMonth.month)"
        if !forceRefresh,
           let cached = cachedLRUValue(for: cacheKey, in: allTimeMostReadCache, order: &allTimeMostReadCacheOrder),
           let reusablePrefixCount = AllTimeMostReadCachePolicy.reusablePrefixCount(
               cachedCount: cached.count,
               requestedLimit: clampedLimit
           ) {
            return Array(cached.prefix(reusablePrefixCount))
        }

        let monthKeys = allTimeTopPageviewsMonths(through: latestMonth)
        guard !monthKeys.isEmpty else { return [] }

        var totalViewsByTitleKey: [String: Int] = [:]
        var titleByKey: [String: String] = [:]

        var startIndex = 0

        while startIndex < monthKeys.count {
            let endIndex = min(
                startIndex + fetchBudget.monthlyRequestBatchSize,
                monthKeys.count
            )
            let batch = monthKeys[startIndex..<endIndex]

            await withTaskGroup(of: [MonthlyTopArticle].self) { group in
                for month in batch {
                    group.addTask { [self] in
                        await self.safeFetchMonthlyTopArticles(
                            year: month.year,
                            month: month.month,
                            perMonthLimit: fetchBudget.perMonthArticleLimit
                        )
                    }
                }

                for await articles in group {
                    guard !Task.isCancelled else { return }
                    for article in articles {
                        totalViewsByTitleKey[article.key, default: 0] += article.views
                        if titleByKey[article.key] == nil {
                            titleByKey[article.key] = article.title
                        }
                    }
                }
            }

            guard !Task.isCancelled else { throw CancellationError() }
            startIndex = endIndex
        }

        let rankedCandidates = totalViewsByTitleKey
            .map { key, totalViews in
                TopPageviewsCandidate(
                    title: titleByKey[key] ?? key,
                    totalViews: totalViews
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalViews == rhs.totalViews {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
                return lhs.totalViews > rhs.totalViews
            }

        guard !rankedCandidates.isEmpty else {
            throw WikipediaError.noResults
        }

        let summaryTargetCount = fetchBudget.summaryTargetCount(
            requestedLimit: clampedLimit,
            availableCandidateCount: rankedCandidates.count
        )
        let summaryTargets = Array(rankedCandidates.prefix(summaryTargetCount))
        var orderedEntries = Array<AllTimeMostReadEntry?>(repeating: nil, count: summaryTargets.count)

        var summaryStartIndex = 0
        while summaryStartIndex < summaryTargets.count {
            let summaryEndIndex = min(
                summaryStartIndex + fetchBudget.summaryRequestBatchSize,
                summaryTargets.count
            )

            await withTaskGroup(of: (Int, AllTimeMostReadEntry?).self) { group in
                for index in summaryStartIndex..<summaryEndIndex {
                    let candidate = summaryTargets[index]
                    group.addTask { [self] in
                        do {
                            let summary = try await self.fetchSummary(candidate.title)
                            let result = SearchResult(
                                id: String(summary.pageId),
                                title: summary.title,
                                description: summary.description ?? summary.extract,
                                thumbnailURL: summary.thumbnailURL
                            )
                            return (
                                index,
                                AllTimeMostReadEntry(
                                    result: result,
                                    totalViews: candidate.totalViews
                                )
                            )
                        } catch {
                            return (index, nil)
                        }
                    }
                }

                for await (index, entry) in group {
                    guard !Task.isCancelled else { return }
                    orderedEntries[index] = entry
                }
            }

            guard !Task.isCancelled else { throw CancellationError() }
            summaryStartIndex = summaryEndIndex
        }

        guard !Task.isCancelled else { throw CancellationError() }

        let enriched = orderedEntries.compactMap { $0 }
        guard !enriched.isEmpty else {
            throw WikipediaError.noResults
        }

        storeLRUValue(
            enriched,
            for: cacheKey,
            in: &allTimeMostReadCache,
            order: &allTimeMostReadCacheOrder,
            maxSize: maxAllTimeMostReadCacheSize
        )

        return Array(enriched.prefix(clampedLimit))
    }

    private func safeFetchMonthlyTopArticles(
        year: Int,
        month: Int,
        perMonthLimit: Int
    ) async -> [MonthlyTopArticle] {
        do {
            return try await fetchMonthlyTopArticles(
                year: year,
                month: month,
                perMonthLimit: perMonthLimit
            )
        } catch {
            if !Task.isCancelled {
                wikipediaServiceLogger.debug("Monthly top articles fetch failed for \(year)-\(month): \(error.localizedDescription, privacy: .public)")
            }
            return []
        }
    }

    private func fetchMonthlyTopArticles(
        year: Int,
        month: Int,
        perMonthLimit: Int
    ) async throws -> [MonthlyTopArticle] {
        let clampedLimit = min(max(perMonthLimit, 20), 300)
        guard let url = URL(
            string: "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/en.wikipedia/all-access/\(year)/\(String(format: "%02d", month))/all-days"
        ) else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url)
        let response = try JSONDecoder().decode(TopPageviewsResponse.self, from: data)
        guard let payload = response.items.first else { return [] }

        return payload.articles
            .prefix(clampedLimit)
            .compactMap { article in
                guard article.views > 0 else { return nil }
                let decodedTitle = decodedTopPageviewsTitle(article.article)
                guard let normalizedTitle = normalizedTopPageviewsArticleTitle(decodedTitle) else {
                    return nil
                }
                let key = normalizedTitleMatchKey(normalizedTitle)
                guard !key.isEmpty else { return nil }
                return MonthlyTopArticle(title: normalizedTitle, key: key, views: article.views)
            }
    }

    func decodedTopPageviewsTitle(_ title: String) -> String {
        let decoded = title.removingPercentEncoding ?? title
        return decoded
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func normalizedTopPageviewsArticleTitle(_ title: String) -> String? {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        let lower = normalized.lowercased()
        if lower == "main page" { return nil }
        if lower.hasPrefix(".") { return nil }
        if lower.contains(":") { return nil }
        if lower.hasPrefix("special ") { return nil }
        if lower.hasPrefix("special:") { return nil }
        if lower.hasPrefix("wikipedia ") { return nil }
        if lower.hasPrefix("wikipedia:") { return nil }
        if lower.hasPrefix("template:") { return nil }
        if lower.hasPrefix("file:") { return nil }
        if lower.hasPrefix("help:") { return nil }
        if lower.hasPrefix("category:") { return nil }
        if lower.hasPrefix("draft:") { return nil }
        if lower.hasPrefix("talk:") { return nil }
        if lower.hasPrefix("user:") { return nil }
        if lower.hasPrefix("module:") { return nil }
        if lower.hasPrefix("mediawiki:") { return nil }
        if lower.hasPrefix("portal:") { return nil }
        if lower.hasPrefix("timedtext:") { return nil }
        if lower.hasPrefix("commons:") { return nil }
        return normalized
    }

    func latestCompletedTopPageviewsMonth(
        endingAt referenceDate: Date
    ) -> (year: Int, month: Int)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let monthComponents = calendar.dateComponents([.year, .month], from: referenceDate)
        guard let startOfCurrentMonth = calendar.date(from: monthComponents),
              let completedMonthDate = calendar.date(byAdding: .month, value: -1, to: startOfCurrentMonth) else {
            return nil
        }

        let completedComponents = calendar.dateComponents([.year, .month], from: completedMonthDate)
        guard let year = completedComponents.year, let month = completedComponents.month else {
            return nil
        }

        return (year: year, month: month)
    }

    func allTimeTopPageviewsMonths(
        through endMonth: (year: Int, month: Int)
    ) -> [(year: Int, month: Int)] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        guard let start = calendar.date(from: DateComponents(year: 2015, month: 7, day: 1)),
              let end = calendar.date(from: DateComponents(year: endMonth.year, month: endMonth.month, day: 1)),
              start <= end else {
            return []
        }

        var months: [(year: Int, month: Int)] = []
        var current = start
        while current <= end {
            let components = calendar.dateComponents([.year, .month], from: current)
            if let year = components.year, let month = components.month {
                months.append((year: year, month: month))
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else {
                break
            }
            current = next
        }
        return months
    }

    func parseDiscoverFeedPayload(_ data: Data, dateKey: String) throws -> DiscoverFeed {
        try parseDiscoverFeed(data, dateKey: dateKey)
    }

    func applyOnThisDayPayload(_ data: Data, to feed: DiscoverFeed) throws -> DiscoverFeed {
        let collections = try parseOnThisDayCollections(data)
        return apply(onThisDayCollections: collections, to: feed)
    }

    func parseDiscoverFeed(_ data: Data, dateKey: String) throws -> DiscoverFeed {
        let response = try JSONDecoder().decode(FeaturedFeedResponse.self, from: data)

        let featuredArticle = response.tfa.flatMap(mapFeedArticle)
        let featuredImage = response.image.flatMap(mapFeaturedImage)

        let newsStories = (response.news ?? [])
            .prefix(12)
            .compactMap(mapNewsStory)

        let inTheNews = deduplicatedArticles(
            response.news?
                .flatMap { $0.links ?? [] }
                .compactMap(mapFeedArticle) ?? []
        )

        let trending = deduplicatedArticles(
            (response.mostread?.articles ?? [])
                .compactMap(mapFeedArticle)
        )

        let onThisDay = (response.onthisday ?? [])
            .prefix(16)
            .compactMap { mapOnThisDayEvent(text: $0.text, year: $0.year, pages: $0.pages) }

        let didYouKnow = (response.dyk ?? [])
            .prefix(12)
            .compactMap { mapDidYouKnowFact(text: $0.text, pages: $0.pages) }

        return DiscoverFeed(
            dateKey: dateKey,
            dateLabel: featuredFeedDisplayLabel(for: dateKey),
            featuredArticle: featuredArticle,
            featuredImage: featuredImage,
            newsStories: newsStories,
            inTheNews: inTheNews,
            trending: Array(trending.prefix(30)),
            onThisDay: onThisDay,
            onThisDaySelected: [],
            onThisDayBirths: [],
            onThisDayDeaths: [],
            holidays: [],
            didYouKnow: didYouKnow
        )
    }

    private func fetchOnThisDayCollections(for date: Date) async throws -> OnThisDayCollections {
        let monthDayKey = onThisDayDatePath(for: date)
        guard let url = URL(string: "\(baseURL)/api/rest_v1/feed/onthisday/all/\(monthDayKey)") else {
            throw WikipediaError.invalidURL
        }
        let data = try await performRequest(url: url)
        return try parseOnThisDayCollections(data)
    }

    private func parseOnThisDayCollections(_ data: Data) throws -> OnThisDayCollections {
        let response = try JSONDecoder().decode(OnThisDayAllResponse.self, from: data)
        return OnThisDayCollections(
            selected: (response.selected ?? [])
                .prefix(12)
                .compactMap { mapOnThisDayEvent(text: $0.text, year: $0.year, pages: $0.pages) },
            events: (response.events ?? [])
                .prefix(18)
                .compactMap { mapOnThisDayEvent(text: $0.text, year: $0.year, pages: $0.pages) },
            births: (response.births ?? [])
                .prefix(12)
                .compactMap { mapOnThisDayEvent(text: $0.text, year: $0.year, pages: $0.pages) },
            deaths: (response.deaths ?? [])
                .prefix(12)
                .compactMap { mapOnThisDayEvent(text: $0.text, year: $0.year, pages: $0.pages) },
            holidays: (response.holidays ?? [])
                .prefix(12)
                .compactMap { mapHolidayItem(text: $0.text, pages: $0.pages) }
        )
    }

    private func apply(onThisDayCollections: OnThisDayCollections, to feed: DiscoverFeed) -> DiscoverFeed {
        DiscoverFeed(
            dateKey: feed.dateKey,
            dateLabel: feed.dateLabel,
            featuredArticle: feed.featuredArticle,
            featuredImage: feed.featuredImage,
            newsStories: feed.newsStories,
            inTheNews: feed.inTheNews,
            trending: feed.trending,
            onThisDay: onThisDayCollections.events.isEmpty ? feed.onThisDay : onThisDayCollections.events,
            onThisDaySelected: onThisDayCollections.selected,
            onThisDayBirths: onThisDayCollections.births,
            onThisDayDeaths: onThisDayCollections.deaths,
            holidays: onThisDayCollections.holidays,
            didYouKnow: feed.didYouKnow
        )
    }

    private func mapOnThisDayEvent(
        text: String?,
        year: Int?,
        pages: [FeaturedFeedResponse.Article]?
    ) -> DiscoverFeed.OnThisDayEvent? {
        let cleanedText = cleanedMetadataText(text)
        guard !cleanedText.isEmpty else { return nil }
        let article = pages?.compactMap(mapFeedArticle).first
        let eventYear = year.map(String.init) ?? "History"
        return DiscoverFeed.OnThisDayEvent(
            id: "\(eventYear)-\(cleanedText)-\(article?.title ?? "none")",
            year: eventYear,
            text: cleanedText,
            article: article
        )
    }

    private func mapDidYouKnowFact(
        text: String?,
        pages: [FeaturedFeedResponse.Article]?
    ) -> DiscoverFeed.DidYouKnowFact? {
        let cleanedText = cleanedMetadataText(text)
        guard !cleanedText.isEmpty else { return nil }
        let article = pages?.compactMap(mapFeedArticle).first
        return DiscoverFeed.DidYouKnowFact(
            id: "\(cleanedText)-\(article?.title ?? "none")",
            text: cleanedText,
            article: article
        )
    }

    private func mapHolidayItem(
        text: String?,
        pages: [FeaturedFeedResponse.Article]?
    ) -> DiscoverFeed.HolidayItem? {
        let cleanedText = cleanedMetadataText(text)
        guard !cleanedText.isEmpty else { return nil }
        let article = pages?.compactMap(mapFeedArticle).first
        return DiscoverFeed.HolidayItem(
            id: "\(cleanedText)-\(article?.title ?? "none")",
            text: cleanedText,
            article: article
        )
    }

    private func mapNewsStory(_ item: FeaturedFeedResponse.NewsItem) -> DiscoverFeed.NewsStory? {
        let storyText = cleanedMetadataText(item.story)
        let links = deduplicatedArticles((item.links ?? []).compactMap(mapFeedArticle))
        guard !storyText.isEmpty || !links.isEmpty else { return nil }
        return DiscoverFeed.NewsStory(
            id: "\(storyText)-\(links.first?.title ?? "none")",
            story: storyText,
            links: links
        )
    }

    private func mapFeaturedImage(_ image: FeaturedFeedResponse.FeaturedImage) -> DiscoverFeed.FeaturedImage? {
        guard let title = image.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return nil
        }

        return DiscoverFeed.FeaturedImage(
            title: title,
            description: cleanedMetadataText(image.description?.text ?? image.description?.html),
            artist: cleanedMetadataText(image.artist?.text ?? image.artist?.html),
            credit: cleanedMetadataText(image.credit?.text ?? image.credit?.html),
            filePageURL: image.filePage.flatMap(URL.init(string:)),
            imageURL: image.image?.source.flatMap(URL.init(string:)),
            thumbnailURL: image.thumbnail?.source.flatMap(URL.init(string:)),
            licenseName: image.license?.type,
            licenseCode: image.license?.code,
            licenseURL: image.license?.url.flatMap(URL.init(string:)),
            entityID: image.entityID
        )
    }

    func cleanedMetadataText(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .processingMetadataHTML()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func deduplicatedArticles(_ articles: [SearchResult]) -> [SearchResult] {
        var seen = Set<String>()
        return articles.filter { article in
            let key = article.title.lowercased().replacingOccurrences(of: "_", with: " ")
            if seen.contains(key) {
                return false
            }
            seen.insert(key)
            return true
        }
    }

    private func mapFeedArticle(_ article: FeaturedFeedResponse.Article) -> SearchResult? {
        let rawTitle = article.normalizedtitle ?? article.title ?? article.titles?.normalized ?? article.titles?.display
        guard let rawTitle else { return nil }
        let title = rawTitle.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "Main Page", !title.hasPrefix("Special:") else { return nil }

        let id = article.pageid.map(String.init) ?? stableFallbackSearchID(for: title)
        let description = article.description ?? article.extract?.trimmingCharacters(in: .whitespacesAndNewlines)

        return SearchResult(
            id: id,
            title: title,
            description: description,
            thumbnailURL: article.thumbnail.flatMap { URL(string: $0.source) }
        )
    }

    func featuredFeedDatePath(for date: Date) -> String {
        featuredFeedDateFormatter.string(from: date)
    }

    func onThisDayDatePath(for date: Date) -> String {
        onThisDayDateFormatter.string(from: date)
    }

    func featuredFeedDisplayLabel(for dateKey: String) -> String {
        guard let date = featuredFeedDateFormatter.date(from: dateKey) else {
            return dateKey
        }
        return AppPresentationFormatting.longDate(
            date,
            locale: .autoupdatingCurrent,
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt
        )
    }

    private struct OnThisDayCollections {
        let selected: [DiscoverFeed.OnThisDayEvent]
        let events: [DiscoverFeed.OnThisDayEvent]
        let births: [DiscoverFeed.OnThisDayEvent]
        let deaths: [DiscoverFeed.OnThisDayEvent]
        let holidays: [DiscoverFeed.HolidayItem]
    }

    private struct TopPageviewsCandidate {
        let title: String
        let totalViews: Int
    }

    private struct MonthlyTopArticle {
        let title: String
        let key: String
        let views: Int
    }

    private struct TopPageviewsResponse: Decodable {
        struct Item: Decodable {
            let articles: [Article]
        }

        struct Article: Decodable {
            let article: String
            let views: Int
        }

        let items: [Item]
    }

    private struct FeaturedFeedResponse: Decodable {
        let tfa: Article?
        let mostread: MostRead?
        let news: [NewsItem]?
        let onthisday: [OnThisDayItem]?
        let dyk: [DidYouKnowItem]?
        let image: FeaturedImage?

        struct MostRead: Decodable {
            let articles: [Article]?
        }

        struct NewsItem: Decodable {
            let story: String?
            let links: [Article]?
        }

        struct OnThisDayItem: Decodable {
            let text: String?
            let year: Int?
            let pages: [Article]?
        }

        struct DidYouKnowItem: Decodable {
            let text: String?
            let pages: [Article]?
        }

        struct FeaturedImage: Decodable {
            struct RichText: Decodable {
                let html: String?
                let text: String?
            }

            struct License: Decodable {
                let type: String?
                let code: String?
                let url: String?
            }

            struct Media: Decodable {
                let source: String?
            }

            let title: String?
            let description: RichText?
            let artist: RichText?
            let credit: RichText?
            let filePage: String?
            let license: License?
            let image: Media?
            let thumbnail: Media?
            let entityID: String?

            enum CodingKeys: String, CodingKey {
                case title
                case description
                case artist
                case credit
                case license
                case image
                case thumbnail
                case filePage = "file_page"
                case entityID = "wb_entity_id"
            }
        }

        struct Article: Decodable {
            let title: String?
            let normalizedtitle: String?
            let description: String?
            let extract: String?
            let pageid: Int?
            let thumbnail: Thumbnail?
            let titles: Titles?

            struct Thumbnail: Decodable {
                let source: String
            }

            struct Titles: Decodable {
                let normalized: String?
                let display: String?
            }
        }
    }

    private struct OnThisDayAllResponse: Decodable {
        struct Item: Decodable {
            let text: String?
            let year: Int?
            let pages: [FeaturedFeedResponse.Article]?
        }

        struct Holiday: Decodable {
            let text: String?
            let pages: [FeaturedFeedResponse.Article]?
        }

        let selected: [Item]?
        let events: [Item]?
        let births: [Item]?
        let deaths: [Item]?
        let holidays: [Holiday]?
    }

    // MARK: - Summary

    /// Fetch article summary/preview
    /// - Parameter title: The article title
}
