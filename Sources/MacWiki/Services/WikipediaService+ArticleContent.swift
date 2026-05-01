import Foundation

extension WikipediaService {
    func fetchArticle(_ title: String) async throws -> ArticleContent {
        let normalizedTitle = normalizedArticleTitle(title)

        // Full metadata cache
        if let cached = cachedFullArticle(for: normalizedTitle) {
            return cached
        }

        // Fast path: get HTML and baseline metadata first.
        let fastContent = try await fetchArticleFast(title)

        // Upgrade to enriched metadata.
        let hydrated = await fetchArticleMetadata(title, html: fastContent.html, wordCount: fastContent.wordCount)
        let content = ArticleContent(
            title: fastContent.title,
            html: fastContent.html,
            pageId: fastContent.pageId,
            metadata: hydrated.items,
            wordCount: hydrated.wordCount
        )

        storeFullArticle(content, for: normalizedTitle)
        removeFastArticle(for: normalizedTitle)
        storeDiskArticleSizeAware(
            content,
            for: normalizedTitle,
            pinned: pinnedArticleTitles.contains(normalizedTitle)
        )

        return content
    }

    /// Fetch article HTML quickly with baseline metadata only.
    /// Designed for first paint speed; expensive metadata can be hydrated separately.
    func fetchArticleFast(_ title: String) async throws -> ArticleContent {
        let detailed = try await fetchArticleFastDetailed(title)
        return detailed.content
    }

    /// Fetch article HTML quickly with source metadata for load-tuning decisions.
    func fetchArticleFastDetailed(_ title: String) async throws -> (content: ArticleContent, source: FastArticleSource) {
        let normalizedTitle = normalizedArticleTitle(title)

        if let full = cachedFullArticle(for: normalizedTitle) {
            return (full, .memoryFull)
        }

        if let fast = cachedFastArticle(for: normalizedTitle) {
            return (fast, .memoryFast)
        }

        if let diskCached = loadDiskArticle(for: normalizedTitle) {
            storeFastArticle(diskCached, for: normalizedTitle)
            return (diskCached, .disk)
        }

        if let inFlight = inFlightFastArticleTasks[normalizedTitle] {
            return try await inFlight.value
        }

        let task = Task<(content: ArticleContent, source: FastArticleSource), Error> { [self] in
            defer { clearInFlightFastArticleTask(for: normalizedTitle) }
            let content = try await fetchFastArticleFromNetwork(title, normalizedTitle: normalizedTitle)
            return (content, .network)
        }
        inFlightFastArticleTasks[normalizedTitle] = task

        return try await task.value
    }

    /// Force-refresh article HTML from network and replace cached copies.
    func refreshArticleFastDetailed(_ title: String) async throws -> (content: ArticleContent, source: FastArticleSource) {
        let normalizedTitle = normalizedArticleTitle(title)
        let wasPinned = pinnedArticleTitles.contains(normalizedTitle)
        invalidateArticleCache(for: normalizedTitle, preservePinnedState: wasPinned)
        let content = try await fetchFastArticleFromNetwork(
            title,
            normalizedTitle: normalizedTitle,
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        return (content, .network)
    }

    func clearInFlightFastArticleTask(for key: String) {
        inFlightFastArticleTasks.removeValue(forKey: key)
    }

    func fetchFastArticleFromNetwork(
        _ title: String,
        normalizedTitle: String,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad
    ) async throws -> ArticleContent {
        guard let encodedTitle = normalizedTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw WikipediaError.invalidURL
        }

        guard let url = URL(string: "\(baseURL)/api/rest_v1/page/mobile-html/\(encodedTitle)") else {
            throw WikipediaError.invalidURL
        }

        let data = try await performRequest(url: url, cachePolicy: cachePolicy)

        guard let html = String(data: data, encoding: .utf8) else {
            throw WikipediaError.decodingError(
                NSError(
                    domain: "WikipediaService",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to decode HTML"]
                )
            )
        }

        let htmlByteCount = html.utf8.count
        let wordCount = estimateWordCountFastPath(fromHTML: html, htmlByteCount: htmlByteCount)
        let baselineMetadata = buildBaselineMetadata(wordCount: wordCount, lastEdited: nil, firstCreated: nil)
        let content = ArticleContent(
            title: title,
            html: html,
            pageId: stableFallbackPageID(for: normalizedTitle),
            metadata: baselineMetadata,
            wordCount: wordCount
        )

        storeFastArticle(content, for: normalizedTitle)
        storeDiskArticleSizeAware(
            content,
            for: normalizedTitle,
            pinned: pinnedArticleTitles.contains(normalizedTitle)
        )

        return content
    }

    /// Enrich baseline article metadata with revision dates + infobox fields.
    func fetchArticleMetadata(_ title: String, html: String, wordCount: Int) async -> HydratedMetadata {
        let normalizedTitle = normalizedArticleTitle(title)
        if let cached = cachedFullArticle(for: normalizedTitle),
           !hasUnknownRevisionMetadata(cached.metadata) {
            return HydratedMetadata(items: cached.metadata, wordCount: cached.wordCount)
        }

        async let revisionMetadata = fetchRevisionMetadataWithTimeout(
            title,
            timeout: .milliseconds(1_200)
        )
        async let resolvedWordCount = resolveHydratedWordCount(for: title, fallback: wordCount)
        let infoboxMetadata = InfoboxParser.extractMetadata(
            from: html,
            maxScanWindow: maxInfoboxScanWindow,
            maxRows: maxInfoboxRows,
            maxItems: maxInfoboxMetadataItems
        ).map { item in
            MetadataItem(label: item.label, value: item.value)
        }
        let revisionInfo = await revisionMetadata
        let canonicalWordCount = await resolvedWordCount

        let baselineMetadata = buildBaselineMetadata(
            wordCount: canonicalWordCount,
            lastEdited: revisionInfo.lastEdited,
            firstCreated: revisionInfo.firstCreated
        )
        let metadata = baselineMetadata + infoboxMetadata

        if let fast = cachedFastArticle(for: normalizedTitle) {
            let enriched = ArticleContent(
                title: fast.title,
                html: fast.html,
                pageId: fast.pageId,
                metadata: metadata,
                wordCount: canonicalWordCount
            )
            storeFullArticle(enriched, for: normalizedTitle)
            removeFastArticle(for: normalizedTitle)
            storeDiskArticleSizeAware(
                enriched,
                for: normalizedTitle,
                pinned: pinnedArticleTitles.contains(normalizedTitle)
            )
        }

        return HydratedMetadata(items: metadata, wordCount: canonicalWordCount)
    }

    func resolveHydratedWordCount(for title: String, fallback: Int) async -> Int {
        do {
            let metadata = try await fetchPageMetadata(title)
            return metadata.wordCount > 0 ? metadata.wordCount : fallback
        } catch {
            return fallback
        }
    }

    func normalizedArticleTitle(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "_")
    }

    func normalizedTitleMatchKey(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stableFallbackPageID(for normalizedTitle: String) -> Int {
        let masked = stableHash(for: normalizedTitle.lowercased()) & UInt64(Int.max)
        let value = Int(masked)
        return value == 0 ? 1 : value
    }

    func stableFallbackSearchID(for title: String) -> String {
        let key = normalizedArticleTitle(title).lowercased()
        return "fallback-\(String(stableHash(for: key), radix: 16))"
    }

    func normalizedMediaURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        return URL(string: trimmed)
    }

    func commonsFilePageURL(for mediaTitle: String) -> URL? {
        let trimmed = mediaTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized: String
        if trimmed.lowercased().hasPrefix("file:") {
            normalized = trimmed
        } else {
            normalized = "File:\(trimmed)"
        }

        let pathTitle = normalized.replacingOccurrences(of: " ", with: "_")
        guard let encoded = pathTitle.addingPercentEncoding(withAllowedCharacters: urlPathAllowedNoSlash) else {
            return nil
        }

        return URL(string: "https://commons.wikimedia.org/wiki/\(encoded)")
    }

}
