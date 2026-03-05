import Foundation
import os

private let wikipediaServiceLogger = Logger(subsystem: "com.macwiki", category: "wikipedia-service")

/// Service for interacting with the Wikipedia API
///
/// Provides search, article content, and summary fetching capabilities
/// with built-in caching and request management.
actor WikipediaService {
    static let shared = WikipediaService()
    
    // MARK: - Types

    private struct DiskArticlePayload: Codable {
        struct MetadataValue: Codable {
            let label: String
            let value: String
        }

        let title: String
        let html: String
        let pageId: Int
        let metadata: [MetadataValue]
        let wordCount: Int
    }

    private struct DiskArticleIndexEnvelope: Codable {
        let version: Int
        var entries: [String: DiskArticleIndexEntry]
    }

    private struct DiskArticleIndexEntry: Codable {
        var fileName: String
        var byteCount: Int
        var lastAccessedAt: TimeInterval
        var isPinned: Bool
    }
    
    private struct DeferredDiskStorePayload: Sendable {
        let content: ArticleContent
        let pinned: Bool
    }
    
    /// Search result from Wikipedia
    struct SearchResult: Identifiable, Sendable, Equatable {
        let id: String
        let title: String
        let description: String?
        let thumbnailURL: URL?
    }

    struct TrendPulse: Sendable, Equatable {
        let points: [Int]
        let latestViews: Int
        let previousViews: Int?
        let windowStart: Date
        let windowEnd: Date
    }

    struct PeakPageviewDay: Identifiable, Sendable, Equatable {
        let date: Date
        let views: Int

        var id: String {
            "\(date.timeIntervalSinceReferenceDate)|\(views)"
        }
    }

    struct AllTimeMostReadEntry: Identifiable, Sendable, Equatable {
        let result: SearchResult
        let totalViews: Int

        var id: String {
            let normalizedTitle = result.title
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(result.id)|\(normalizedTitle)"
        }
    }

    struct VisualContextImage: Identifiable, Sendable, Equatable {
        let id: String
        let mediaTitle: String
        let caption: String?
        let thumbnailURL: URL
        let filePageURL: URL?
    }

    struct DiscoverFeed: Sendable, Equatable {
        struct OnThisDayEvent: Identifiable, Sendable, Equatable {
            let id: String
            let year: String
            let text: String
            let article: SearchResult?
        }

        struct DidYouKnowFact: Identifiable, Sendable, Equatable {
            let id: String
            let text: String
            let article: SearchResult?
        }

        struct NewsStory: Identifiable, Sendable, Equatable {
            let id: String
            let story: String
            let links: [SearchResult]
        }

        struct FeaturedImage: Sendable, Equatable {
            let title: String
            let description: String?
            let artist: String?
            let credit: String?
            let filePageURL: URL?
            let imageURL: URL?
            let thumbnailURL: URL?
            let licenseName: String?
            let licenseCode: String?
            let licenseURL: URL?
            let entityID: String?
        }

        struct HolidayItem: Identifiable, Sendable, Equatable {
            let id: String
            let text: String
            let article: SearchResult?
        }

        let dateKey: String
        let dateLabel: String
        let featuredArticle: SearchResult?
        let featuredImage: FeaturedImage?
        let newsStories: [NewsStory]
        let inTheNews: [SearchResult]
        let trending: [SearchResult]
        let onThisDay: [OnThisDayEvent]
        let onThisDaySelected: [OnThisDayEvent]
        let onThisDayBirths: [OnThisDayEvent]
        let onThisDayDeaths: [OnThisDayEvent]
        let holidays: [HolidayItem]
        let didYouKnow: [DidYouKnowFact]
    }
    
    /// Metadata item from the infobox
    struct MetadataItem: Identifiable, Sendable, Equatable {
        let id = UUID()
        let label: String
        let value: String
    }

    /// Full article content
    struct ArticleContent: Sendable {
        let title: String
        let html: String
        let pageId: Int
        let metadata: [MetadataItem]
        let wordCount: Int
    }

    /// Enriched metadata payload, including the resolved word count used for display.
    struct HydratedMetadata: Sendable {
        let items: [MetadataItem]
        let wordCount: Int
    }

    struct CacheMetrics: Sendable {
        let fullArticleEntries: Int
        let fullArticleBytes: Int
        let fastArticleEntries: Int
        let fastArticleBytes: Int
        let diskArticleEntries: Int
        let diskArticleBytes: Int
        let pinnedArticleEntries: Int
    }

    enum FastArticleSource: Sendable {
        case memoryFull
        case memoryFast
        case disk
        case network
    }

    init(
        cacheDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager

        let baseCacheDirectory = cacheDirectoryURL ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MacWiki", isDirectory: true)

        if let baseCacheDirectory {
            let articleCacheDirectory = baseCacheDirectory
                .appendingPathComponent("ArticleBodyCache", isDirectory: true)
            self.diskArticleCacheDirectoryURL = articleCacheDirectory
            self.diskArticleCacheIndexURL = articleCacheDirectory.appendingPathComponent("index.json")
            try? fileManager.createDirectory(
                at: articleCacheDirectory,
                withIntermediateDirectories: true
            )
        } else {
            self.diskArticleCacheDirectoryURL = nil
            self.diskArticleCacheIndexURL = nil
        }
    }
    
    // ... (ArticleSummary struct remains same)

    // ... (WikipediaError enum remains same)
    
    // ... (Configuration & Caching remain same)
    
    // ... (Search methods remain same)

    // MARK: - Article Content
    
    /// Fetch full article content as mobile-html
    /// - Parameter title: The article title
    /// - Returns: Article content with HTML and Metadata
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

    private func clearInFlightFastArticleTask(for key: String) {
        inFlightFastArticleTasks.removeValue(forKey: key)
    }

    private func fetchFastArticleFromNetwork(
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
        if let cached = cachedFullArticle(for: normalizedTitle) {
            return HydratedMetadata(items: cached.metadata, wordCount: cached.wordCount)
        }

        async let revisionMetadata = fetchRevisionMetadataWithTimeout(
            title,
            timeout: .milliseconds(180)
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

    private func resolveHydratedWordCount(for title: String, fallback: Int) async -> Int {
        do {
            let metadata = try await fetchPageMetadata(title)
            return metadata.wordCount > 0 ? metadata.wordCount : fallback
        } catch {
            return fallback
        }
    }

    private func normalizedArticleTitle(_ title: String) -> String {
        title.replacingOccurrences(of: " ", with: "_")
    }

    private func normalizedTitleMatchKey(_ title: String) -> String {
        title
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stableFallbackPageID(for normalizedTitle: String) -> Int {
        let masked = stableHash(for: normalizedTitle.lowercased()) & UInt64(Int.max)
        let value = Int(masked)
        return value == 0 ? 1 : value
    }

    private func stableFallbackSearchID(for title: String) -> String {
        let key = normalizedArticleTitle(title).lowercased()
        return "fallback-\(String(stableHash(for: key), radix: 16))"
    }

    private func normalizedMediaURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:\(trimmed)")
        }
        return URL(string: trimmed)
    }

    private func commonsFilePageURL(for mediaTitle: String) -> URL? {
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

    private func articleByteCount(_ content: ArticleContent) -> Int {
        content.html.utf8.count
    }

    private func cachedFullArticle(for key: String) -> ArticleContent? {
        guard let cached = articleCache[key] else { return nil }
        articleCacheOrder.removeAll { $0 == key }
        articleCacheOrder.append(key)
        return cached
    }

    private func cachedFastArticle(for key: String) -> ArticleContent? {
        guard let cached = articleFastCache[key] else { return nil }
        articleFastCacheOrder.removeAll { $0 == key }
        articleFastCacheOrder.append(key)
        return cached
    }

    private func storeFullArticle(_ content: ArticleContent, for key: String) {
        let byteCount = articleByteCount(content)
        guard byteCount <= maxCachedArticleHTMLBytes else {
            removeFullArticle(for: key)
            return
        }

        if let existing = articleCache[key] {
            articleCacheTotalBytes -= articleByteCount(existing)
        }

        articleCache[key] = content
        articleCacheTotalBytes += byteCount
        articleCacheOrder.removeAll { $0 == key }
        articleCacheOrder.append(key)
        trimFullArticleCacheIfNeeded()
    }

    private func storeFastArticle(_ content: ArticleContent, for key: String) {
        let byteCount = articleByteCount(content)
        guard byteCount <= maxCachedArticleHTMLBytes else {
            removeFastArticle(for: key)
            return
        }

        if let existing = articleFastCache[key] {
            articleFastCacheTotalBytes -= articleByteCount(existing)
        }

        articleFastCache[key] = content
        articleFastCacheTotalBytes += byteCount
        articleFastCacheOrder.removeAll { $0 == key }
        articleFastCacheOrder.append(key)
        trimFastArticleCacheIfNeeded()
    }

    private func removeFullArticle(for key: String) {
        if let existing = articleCache.removeValue(forKey: key) {
            articleCacheTotalBytes -= articleByteCount(existing)
        }
        articleCacheOrder.removeAll { $0 == key }
    }

    private func removeFastArticle(for key: String) {
        if let existing = articleFastCache.removeValue(forKey: key) {
            articleFastCacheTotalBytes -= articleByteCount(existing)
        }
        articleFastCacheOrder.removeAll { $0 == key }
    }

    private func invalidateArticleCache(for key: String, preservePinnedState: Bool) {
        if let inFlightTask = inFlightFastArticleTasks.removeValue(forKey: key) {
            inFlightTask.cancel()
        }

        removeFullArticle(for: key)
        removeFastArticle(for: key)
        deferredDiskStorePayloadByKey.removeValue(forKey: key)

        ensureDiskArticleCacheIndexLoaded()
        removeDiskArticle(for: key)
        if preservePinnedState {
            pinnedArticleTitles.insert(key)
        }
        persistDiskArticleCacheIndex(force: true)
    }

    private func trimFullArticleCacheIfNeeded() {
        while articleCache.count > maxArticleCacheSize || articleCacheTotalBytes > maxArticleCacheBytes {
            guard !articleCacheOrder.isEmpty else { break }
            let evictIndex = articleCacheOrder.firstIndex(where: { !pinnedArticleTitles.contains($0) }) ?? 0
            let evictedKey = articleCacheOrder.remove(at: evictIndex)
            if let evicted = articleCache.removeValue(forKey: evictedKey) {
                articleCacheTotalBytes -= articleByteCount(evicted)
            }
        }
    }

    private func trimFastArticleCacheIfNeeded() {
        while articleFastCache.count > maxArticleFastCacheSize || articleFastCacheTotalBytes > maxArticleFastCacheBytes {
            guard !articleFastCacheOrder.isEmpty else { break }
            let evictIndex = articleFastCacheOrder.firstIndex(where: { !pinnedArticleTitles.contains($0) }) ?? 0
            let evictedKey = articleFastCacheOrder.remove(at: evictIndex)
            if let evicted = articleFastCache.removeValue(forKey: evictedKey) {
                articleFastCacheTotalBytes -= articleByteCount(evicted)
            }
        }
    }

    private func ensureDiskArticleCacheIndexLoaded() {
        guard !didLoadDiskArticleCacheIndex else { return }
        didLoadDiskArticleCacheIndex = true

        guard let diskArticleCacheDirectoryURL else { return }
        try? fileManager.createDirectory(at: diskArticleCacheDirectoryURL, withIntermediateDirectories: true)

        guard let diskArticleCacheIndexURL,
              let data = try? Data(contentsOf: diskArticleCacheIndexURL),
              let envelope = try? JSONDecoder().decode(DiskArticleIndexEnvelope.self, from: data),
              envelope.version == diskArticleCacheVersion else {
            diskArticleCacheIndex = [:]
            return
        }

        var cleanedEntries: [String: DiskArticleIndexEntry] = [:]
        for (key, entry) in envelope.entries {
            guard let url = diskArticleFileURL(fileName: entry.fileName),
                  fileManager.fileExists(atPath: url.path) else {
                continue
            }
            cleanedEntries[key] = entry
        }

        diskArticleCacheIndex = cleanedEntries
        pinnedArticleTitles = Set(cleanedEntries.compactMap { $0.value.isPinned ? $0.key : nil })
        evictDiskArticlesIfNeeded()
        persistDiskArticleCacheIndex(force: true)
    }

    private func persistDiskArticleCacheIndex(force: Bool = false) {
        guard let diskArticleCacheIndexURL else { return }

        let now = Date().timeIntervalSince1970
        if !force, (now - lastDiskIndexPersistAt) < diskIndexTouchPersistInterval {
            return
        }

        let envelope = DiskArticleIndexEnvelope(
            version: diskArticleCacheVersion,
            entries: diskArticleCacheIndex
        )
        guard let encoded = try? JSONEncoder().encode(envelope) else { return }
        try? encoded.write(to: diskArticleCacheIndexURL, options: .atomic)
        lastDiskIndexPersistAt = now
    }

    private func diskArticleFileURL(fileName: String) -> URL? {
        diskArticleCacheDirectoryURL?.appendingPathComponent(fileName)
    }

    private func stableHash(for key: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    private func diskArticleFileName(for key: String) -> String {
        let hash = stableHash(for: key)
        return "article-\(String(hash, radix: 16)).json"
    }

    private func storeDiskArticle(_ content: ArticleContent, for key: String, pinned: Bool) {
        let htmlByteCount = content.html.utf8.count
        guard htmlByteCount <= maxDiskCachedArticleHTMLBytes else { return }
        ensureDiskArticleCacheIndexLoaded()

        let metadataValues = content.metadata.map { DiskArticlePayload.MetadataValue(label: $0.label, value: $0.value) }
        let payload = DiskArticlePayload(
            title: content.title,
            html: content.html,
            pageId: content.pageId,
            metadata: metadataValues,
            wordCount: content.wordCount
        )

        guard let encoded = try? JSONEncoder().encode(payload) else { return }
        let fileName = diskArticleCacheIndex[key]?.fileName ?? diskArticleFileName(for: key)
        guard let fileURL = diskArticleFileURL(fileName: fileName) else { return }

        do {
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        diskArticleCacheIndex[key] = DiskArticleIndexEntry(
            fileName: fileName,
            byteCount: encoded.count,
            lastAccessedAt: Date().timeIntervalSince1970,
            isPinned: pinned
        )
        evictDiskArticlesIfNeeded()
        persistDiskArticleCacheIndex(force: true)
    }
    
    private func storeDiskArticleSizeAware(_ content: ArticleContent, for key: String, pinned: Bool) {
        let htmlByteCount = content.html.utf8.count
        if htmlByteCount <= deferredDiskStoreThresholdBytes {
            storeDiskArticle(content, for: key, pinned: pinned)
            return
        }
        
        // Large payloads can take meaningful time to encode/write. Keep first paint
        // responsive by deferring disk persistence to a utility worker.
        deferredDiskStorePayloadByKey[key] = DeferredDiskStorePayload(content: content, pinned: pinned)
        startDeferredDiskStoreWorkerIfNeeded()
    }
    
    private func startDeferredDiskStoreWorkerIfNeeded() {
        guard deferredDiskStoreWorkerTask == nil else { return }
        
        deferredDiskStoreWorkerTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runDeferredDiskStoreWorker()
        }
    }
    
    private func runDeferredDiskStoreWorker() async {
        defer {
            deferredDiskStoreWorkerTask = nil
            if !deferredDiskStorePayloadByKey.isEmpty {
                startDeferredDiskStoreWorkerIfNeeded()
            }
        }
        
        // Give the open path headroom to reach first visible paint.
        try? await Task.sleep(nanoseconds: deferredDiskStoreInitialDelayNs)
        
        while !Task.isCancelled {
            guard let key = deferredDiskStorePayloadByKey.keys.first,
                  let payload = deferredDiskStorePayloadByKey.removeValue(forKey: key) else {
                break
            }
            storeDiskArticle(payload.content, for: key, pinned: payload.pinned)
            try? await Task.sleep(nanoseconds: deferredDiskStoreInterItemDelayNs)
        }
    }

    private func loadDiskArticle(for key: String) -> ArticleContent? {
        ensureDiskArticleCacheIndexLoaded()
        guard var entry = diskArticleCacheIndex[key],
              let fileURL = diskArticleFileURL(fileName: entry.fileName),
              let encoded = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(DiskArticlePayload.self, from: encoded) else {
            removeDiskArticle(for: key)
            return nil
        }

        entry.lastAccessedAt = Date().timeIntervalSince1970
        diskArticleCacheIndex[key] = entry
        persistDiskArticleCacheIndex(force: false)

        return ArticleContent(
            title: payload.title,
            html: payload.html,
            pageId: payload.pageId,
            metadata: payload.metadata.map { MetadataItem(label: $0.label, value: $0.value) },
            wordCount: payload.wordCount
        )
    }

    private func removeDiskArticle(for key: String) {
        guard let entry = diskArticleCacheIndex.removeValue(forKey: key) else { return }
        if entry.isPinned {
            pinnedArticleTitles.remove(key)
        }
        if let fileURL = diskArticleFileURL(fileName: entry.fileName) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func evictDiskArticlesIfNeeded() {
        var totalBytes = diskArticleCacheIndex.values.reduce(0) { $0 + $1.byteCount }

        guard diskArticleCacheIndex.count > maxDiskArticleCacheEntries || totalBytes > maxDiskArticleCacheBytes else {
            return
        }

        let evictionCandidates = diskArticleCacheIndex
            .filter { !$0.value.isPinned }
            .sorted { $0.value.lastAccessedAt < $1.value.lastAccessedAt }

        for candidate in evictionCandidates {
            guard diskArticleCacheIndex.count > maxDiskArticleCacheEntries || totalBytes > maxDiskArticleCacheBytes else {
                break
            }
            totalBytes -= candidate.value.byteCount
            removeDiskArticle(for: candidate.key)
        }
    }

    private func fetchRevisionMetadataWithTimeout(_ title: String, timeout: Duration) async -> RevisionMetadata {
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
    private func estimateWordCount(fromHTML html: String) -> Int {
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

    private func estimateWordCount(fromPlainText text: String) -> Int {
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
    private func estimateWordCountFastPath(fromHTML html: String, htmlByteCount: Int) -> Int {
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
    
    private func buildBaselineMetadata(wordCount: Int, lastEdited: Date?, firstCreated: Date?) -> [MetadataItem] {
        [
            MetadataItem(label: "Word count", value: formatWordCount(wordCount)),
            MetadataItem(label: "Last edited", value: formatMetadataDate(lastEdited)),
            MetadataItem(label: "First created", value: formatMetadataDate(firstCreated))
        ]
    }

    private func formatWordCount(_ count: Int) -> String {
        let countString = NumberFormatter.localizedString(from: NSNumber(value: count), number: .decimal)
        return count == 1 ? "\(countString) word" : "\(countString) words"
    }

    private func formatMetadataDate(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
    
    /// Article summary/preview
    struct ArticleSummary: Sendable {
        let title: String
        let description: String?
        let extract: String?
        let thumbnailURL: URL?
        let pageId: Int
    }
    
    /// Errors that can occur during API operations
    enum WikipediaError: LocalizedError {
        case invalidURL
        case networkError(Error)
        case decodingError(Error)
        case noResults
        case rateLimited
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Wikipedia URL"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .decodingError(let error):
                return "Failed to parse response: \(error.localizedDescription)"
            case .noResults:
                return "No results found"
            case .rateLimited:
                return "Too many requests. Please wait a moment."
            }
        }
    }
    
    // MARK: - Configuration
    
    private let baseURL = "https://en.wikipedia.org"
    private let userAgent = "MacWiki/1.0 (https://github.com/tombunting/MacWiki)"
    private let fileManager: FileManager
    
    // MARK: - Caching
    
    private var searchCache: [String: [SearchResult]] = [:]
    private var summaryCache: [String: ArticleSummary] = [:]
    private var articleCache: [String: ArticleContent] = [:]
    private var articleFastCache: [String: ArticleContent] = [:]
    private var inFlightSummaryTasks: [String: Task<ArticleSummary, Error>] = [:]
    private var inFlightFastArticleTasks: [String: Task<(content: ArticleContent, source: FastArticleSource), Error>] = [:]
    private var inFlightPageMetadataTasks: [String: Task<PageMetadata, Error>] = [:]
    private var deferredDiskStorePayloadByKey: [String: DeferredDiskStorePayload] = [:]
    private var deferredDiskStoreWorkerTask: Task<Void, Never>?
    private var articleCacheOrder: [String] = []
    private var articleFastCacheOrder: [String] = []
    private var articleCacheTotalBytes: Int = 0
    private var articleFastCacheTotalBytes: Int = 0
    private var trendingCache: [String: [SearchResult]] = [:]
    private var discoverCache: [String: DiscoverFeed] = [:]
    private var discoverCacheFetchedAt: [String: Date] = [:]
    private var pageMetadataCache: [String: PageMetadata] = [:]
    private var trendPulseCache: [String: TrendPulse] = [:]
    private var visualContextCache: [String: [VisualContextImage]] = [:]
    private var peakPageviewDaysCache: [String: [PeakPageviewDay]] = [:]
    private var allTimeMostReadCache: [String: [AllTimeMostReadEntry]] = [:]
    private var pinnedArticleTitles: Set<String> = []

    private let diskArticleCacheDirectoryURL: URL?
    private let diskArticleCacheIndexURL: URL?
    private var diskArticleCacheIndex: [String: DiskArticleIndexEntry] = [:]
    private var didLoadDiskArticleCacheIndex = false
    private var lastDiskIndexPersistAt: TimeInterval = 0
    
    private let maxSearchCacheSize = 100
    private let maxSummaryCacheSize = 100
    private let maxArticleCacheSize = 12
    private let maxArticleFastCacheSize = 10
    private let maxArticleCacheBytes = 9_000_000
    private let maxArticleFastCacheBytes = 7_000_000
    private let maxCachedArticleHTMLBytes = 900_000
    private let maxDiskCachedArticleHTMLBytes = 1_500_000
    private let deferredDiskStoreThresholdBytes = 420_000
    private let deferredDiskStoreInitialDelayNs: UInt64 = 140_000_000
    private let deferredDiskStoreInterItemDelayNs: UInt64 = 30_000_000
    private let maxDiskArticleCacheEntries = 300
    private let maxDiskArticleCacheBytes = 220_000_000
    private let diskIndexTouchPersistInterval: TimeInterval = 30
    private let diskArticleCacheVersion = 1
    private let fastPathWordCountExactScanBytes = 420_000
    private let fastPathWordCountSampleBytes = 220_000
    private let maxTrendingCacheSize = 14
    private let maxDiscoverCacheSize = 14
    private let discoverTodayCacheTTL: TimeInterval = 15 * 60
    private let maxPageMetadataCacheSize = 240
    private let maxTrendPulseCacheSize = 240
    private let maxVisualContextCacheSize = 120
    private let maxPeakPageviewCacheSize = 180
    private let maxAllTimeMostReadCacheSize = 8
    private let maxInfoboxScanWindow = 220_000
    private let maxInfoboxRows = 120
    private let maxInfoboxMetadataItems = 80
    
    // MARK: - Search
    
    /// Search Wikipedia for articles matching a query
    /// - Parameter query: The search term
    /// - Returns: Array of search results
    func search(_ query: String) async throws -> [SearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return [] }
        
        // Check cache
        if let cached = searchCache[trimmedQuery.lowercased()] {
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
        if searchCache.count >= maxSearchCacheSize {
            searchCache.removeAll()
        }
        searchCache[trimmedQuery.lowercased()] = results
        
        return results
    }
    
    private func parseSearchResults(_ data: Data) throws -> [SearchResult] {
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
    /// Includes featured article, in-the-news links, most read, this-day events, and did-you-know items.
    func fetchDiscoverFeed(referenceDate: Date = Date(), forceRefresh: Bool = false) async throws -> DiscoverFeed {
        let calendar = Calendar.current
        let fallbackDate = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let candidates = [referenceDate, fallbackDate]
        let todayDateKey = featuredFeedDatePath(for: Date())

        var lastError: Error?

        for candidate in candidates {
            let dateKey = featuredFeedDatePath(for: candidate)

            if !forceRefresh, let cached = discoverCache[dateKey] {
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
                if discoverCache.count >= maxDiscoverCacheSize {
                    discoverCache.removeAll()
                    discoverCacheFetchedAt.removeAll()
                }
                discoverCache[dateKey] = feed
                discoverCacheFetchedAt[dateKey] = Date()
                if trendingCache.count >= maxTrendingCacheSize {
                    trendingCache.removeAll()
                }
                trendingCache[dateKey] = feed.trending
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

    private func shouldRefreshDiscoverCache(
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
        let startDate = Calendar.current.date(byAdding: .day, value: -(clampedDays - 1), to: endDate) ?? endDate
        let endKey = pageviewsDateFormatter.string(from: endDate)
        let cacheKey = "\(normalizedTitle.lowercased())|\(endKey)|\(clampedDays)"

        if let cached = trendPulseCache[cacheKey] {
            return cached
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
        if trendPulseCache.count >= maxTrendPulseCacheSize {
            trendPulseCache.removeAll()
        }
        trendPulseCache[cacheKey] = pulse
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
        if let cached = visualContextCache[cacheKey] {
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
        if visualContextCache.count >= maxVisualContextCacheSize {
            visualContextCache.removeAll()
        }
        visualContextCache[cacheKey] = result
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

        if let cached = peakPageviewDaysCache[cacheKey] {
            return cached
        }

        // Wikimedia pageview dataset starts at 2015-07-01 for this endpoint.
        guard let historyStart = pageviewsDateFormatter.date(from: "20150701") else {
            return []
        }
        if endDate < historyStart {
            return []
        }

        let articlePath = normalizedTitle
        guard
            let encodedArticle = articlePath.addingPercentEncoding(withAllowedCharacters: urlPathAllowedNoSlash)
        else {
            throw WikipediaError.invalidURL
        }

        guard let url = URL(
            string: "https://wikimedia.org/api/rest_v1/metrics/pageviews/per-article/en.wikipedia/all-access/user/\(encodedArticle)/daily/20150701/\(endKey)"
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
        if peakPageviewDaysCache.count >= maxPeakPageviewCacheSize {
            peakPageviewDaysCache.removeAll()
        }
        peakPageviewDaysCache[cacheKey] = result
        return result
    }

    /// Fetch all-time most-read articles using aggregated monthly top pageview charts.
    /// "All-time" here maps to the full available Wikimedia pageviews history (since 2015-07).
    func fetchAllTimeMostRead(
        limit: Int = 36,
        referenceDate: Date = Date()
    ) async throws -> [AllTimeMostReadEntry] {
        let clampedLimit = min(max(limit, 1), 80)
        guard let latestMonth = latestCompletedTopPageviewsMonth(endingAt: referenceDate) else {
            return []
        }

        let cacheKey = "all-time-\(latestMonth.year)-\(latestMonth.month)"
        if let cached = allTimeMostReadCache[cacheKey], !cached.isEmpty {
            return Array(cached.prefix(clampedLimit))
        }

        let monthKeys = allTimeTopPageviewsMonths(through: latestMonth)
        guard !monthKeys.isEmpty else { return [] }

        var totalViewsByTitleKey: [String: Int] = [:]
        var titleByKey: [String: String] = [:]

        let monthlyFetchBatchSize = 6
        let perMonthTopLimit = 180
        var startIndex = 0

        while startIndex < monthKeys.count {
            let endIndex = min(startIndex + monthlyFetchBatchSize, monthKeys.count)
            let batch = monthKeys[startIndex..<endIndex]

            await withTaskGroup(of: [MonthlyTopArticle].self) { group in
                for month in batch {
                    group.addTask { [self] in
                        await self.safeFetchMonthlyTopArticles(
                            year: month.year,
                            month: month.month,
                            perMonthLimit: perMonthTopLimit
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

        let summaryTargetCount = min(max(clampedLimit * 3, 80), rankedCandidates.count)
        let summaryTargets = Array(rankedCandidates.prefix(summaryTargetCount))
        var orderedEntries = Array<AllTimeMostReadEntry?>(repeating: nil, count: summaryTargets.count)

        await withTaskGroup(of: (Int, AllTimeMostReadEntry?).self) { group in
            for (index, candidate) in summaryTargets.enumerated() {
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

        let enriched = orderedEntries.compactMap { $0 }
        guard !enriched.isEmpty else {
            throw WikipediaError.noResults
        }

        if allTimeMostReadCache.count >= maxAllTimeMostReadCacheSize {
            allTimeMostReadCache.removeAll()
        }
        allTimeMostReadCache[cacheKey] = enriched

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

    private func decodedTopPageviewsTitle(_ title: String) -> String {
        let decoded = title.removingPercentEncoding ?? title
        return decoded
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedTopPageviewsArticleTitle(_ title: String) -> String? {
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

    private func latestCompletedTopPageviewsMonth(
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

    private func allTimeTopPageviewsMonths(
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

    private func parseDiscoverFeed(_ data: Data, dateKey: String) throws -> DiscoverFeed {
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

    private func cleanedMetadataText(_ text: String?) -> String {
        guard let text else { return "" }
        return text
            .processingMetadataHTML()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deduplicatedArticles(_ articles: [SearchResult]) -> [SearchResult] {
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

    private func featuredFeedDatePath(for date: Date) -> String {
        featuredFeedDateFormatter.string(from: date)
    }

    private func onThisDayDatePath(for date: Date) -> String {
        onThisDayDateFormatter.string(from: date)
    }

    private func featuredFeedDisplayLabel(for dateKey: String) -> String {
        guard let date = featuredFeedDateFormatter.date(from: dateKey) else {
            return dateKey
        }
        return featuredFeedDisplayFormatter.string(from: date)
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
    /// - Returns: Article summary with description and thumbnail
    func fetchSummary(_ title: String) async throws -> ArticleSummary {
        let normalizedTitle = title.replacingOccurrences(of: " ", with: "_")
        
        // Check cache
        if let cached = summaryCache[normalizedTitle] {
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

            if summaryCache.count >= maxSummaryCacheSize {
                summaryCache.removeAll()
            }
            summaryCache[normalizedTitle] = summary

            return summary
        }
        inFlightSummaryTasks[normalizedTitle] = task

        return try await task.value
    }
    
    private func parseSummary(_ data: Data, title: String) throws -> ArticleSummary {
        struct Response: Decodable {
            let pageid: Int
            let title: String
            let description: String?
            let extract: String?
            let thumbnail: Thumbnail?
            
            struct Thumbnail: Decodable {
                let source: String
            }
        }
        
        do {
            let response = try JSONDecoder().decode(Response.self, from: data)
            
            return ArticleSummary(
                title: response.title,
                description: response.description,
                extract: response.extract,
                thumbnailURL: response.thumbnail.flatMap { URL(string: $0.source) },
                pageId: response.pageid
            )
        } catch {
            throw WikipediaError.decodingError(error)
        }
    }

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
    
    /// Fetch lightweight metadata (word count) for an article
    func fetchPageMetadata(_ title: String) async throws -> PageMetadata {
        let normalizedTitle = normalizedArticleTitle(title)

        if let cached = pageMetadataCache[normalizedTitle] {
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

    private func fetchPageMetadataFromNetwork(_ title: String) async throws -> PageMetadata {
        if let metadata = try await fetchPageMetadataFromSearch(title) {
            return metadata
        }

        return try await fetchPageMetadataFromExtract(title)
    }

    private func fetchPageMetadataFromSearch(_ title: String) async throws -> PageMetadata? {
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

    private func fetchPageMetadataFromExtract(_ title: String) async throws -> PageMetadata {
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

    private func clearInFlightPageMetadataTask(for normalizedTitle: String) {
        inFlightPageMetadataTasks.removeValue(forKey: normalizedTitle)
    }

    private func clearInFlightSummaryTask(for normalizedTitle: String) {
        inFlightSummaryTasks.removeValue(forKey: normalizedTitle)
    }

    private func storePageMetadata(_ metadata: PageMetadata, for normalizedTitle: String) {
        if pageMetadataCache.count >= maxPageMetadataCacheSize {
            pageMetadataCache.removeAll(keepingCapacity: true)
        }
        pageMetadataCache[normalizedTitle] = metadata
    }

    /// Fetch revision timestamps for last edited and first created dates
    private func fetchRevisionMetadata(_ title: String) async -> RevisionMetadata {
        async let lastEditedResult = fetchRevisionTimestamp(title, direction: .older)
        async let firstCreatedResult = fetchRevisionTimestamp(title, direction: .newer)

        let lastEdited = try? await lastEditedResult
        let firstCreated = try? await firstCreatedResult

        return RevisionMetadata(lastEdited: lastEdited, firstCreated: firstCreated)
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

    private func parseRevisionTimestamp(_ timestamp: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: timestamp) {
            return date
        }
        return iso8601Formatter.date(from: timestamp)
    }

    private func parsePageviewsTimestamp(_ timestamp: String) -> Date? {
        guard timestamp.count >= 8 else { return nil }
        let dayToken = String(timestamp.prefix(8))
        return pageviewsDateFormatter.date(from: dayToken)
    }
    
    // MARK: - Network
    
    private func performRequest(
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
                let (data, response) = try await urlSession.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    switch httpResponse.statusCode {
                    case 200..<300:
                        return data
                    case 429:
                        if attempt < maxAttempts - 1 {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            continue
                        }
                        throw WikipediaError.rateLimited
                    case 500..<600:
                        if attempt < maxAttempts - 1 {
                            try? await Task.sleep(nanoseconds: 260_000_000)
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
            } catch let error as WikipediaError {
                throw error
            } catch let error as URLError {
                if attempt < maxAttempts - 1 && shouldRetryNetworkError(error) {
                    try? await Task.sleep(nanoseconds: 220_000_000)
                    continue
                }
                throw WikipediaError.networkError(error)
            } catch {
                throw WikipediaError.networkError(error)
            }
        }

        throw WikipediaError.noResults
    }

    private func isMobileHTMLRequest(_ url: URL) -> Bool {
        url.path.contains("/api/rest_v1/page/mobile-html/")
    }

    private func shouldRetryNetworkError(_ error: URLError) -> Bool {
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

    private let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let featuredFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private let onThisDayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    private let pageviewsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    private let urlPathAllowedNoSlash: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    private let featuredFeedDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .none
        formatter.dateStyle = .long
        return formatter
    }()

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()
    
    // MARK: - Cache Management

    func setArticlePinned(_ title: String, pinned: Bool) {
        let key = normalizedArticleTitle(title)
        if pinned {
            pinnedArticleTitles.insert(key)
        } else {
            pinnedArticleTitles.remove(key)
        }

        ensureDiskArticleCacheIndexLoaded()
        if var entry = diskArticleCacheIndex[key] {
            entry.isPinned = pinned
            diskArticleCacheIndex[key] = entry
            if !pinned {
                evictDiskArticlesIfNeeded()
            }
            persistDiskArticleCacheIndex(force: true)
        }
    }

    func replacePinnedArticleTitles(_ titles: [String]) {
        ensureDiskArticleCacheIndexLoaded()
        let normalized = Set(titles.map(normalizedArticleTitle))
        pinnedArticleTitles = normalized

        var didChange = false
        for key in Array(diskArticleCacheIndex.keys) {
            guard var entry = diskArticleCacheIndex[key] else { continue }
            let shouldBePinned = normalized.contains(key)
            if entry.isPinned != shouldBePinned {
                entry.isPinned = shouldBePinned
                diskArticleCacheIndex[key] = entry
                didChange = true
            }
        }

        evictDiskArticlesIfNeeded()
        if didChange {
            persistDiskArticleCacheIndex(force: true)
        }
    }

    func clearInMemoryArticleCache() {
        articleCache.removeAll()
        articleFastCache.removeAll()
        articleCacheOrder.removeAll()
        articleFastCacheOrder.removeAll()
        articleCacheTotalBytes = 0
        articleFastCacheTotalBytes = 0
        pageMetadataCache.removeAll()
        trendPulseCache.removeAll()
        visualContextCache.removeAll()
        peakPageviewDaysCache.removeAll()
        inFlightSummaryTasks.values.forEach { $0.cancel() }
        inFlightSummaryTasks.removeAll()
        inFlightPageMetadataTasks.values.forEach { $0.cancel() }
        inFlightPageMetadataTasks.removeAll()
    }

    func clearDiskArticleCache(includePinned: Bool = true) {
        ensureDiskArticleCacheIndexLoaded()
        deferredDiskStoreWorkerTask?.cancel()
        deferredDiskStoreWorkerTask = nil
        deferredDiskStorePayloadByKey.removeAll()

        if includePinned {
            for key in Array(diskArticleCacheIndex.keys) {
                removeDiskArticle(for: key)
            }
            pinnedArticleTitles.removeAll()
        } else {
            for (key, entry) in Array(diskArticleCacheIndex) where !entry.isPinned {
                removeDiskArticle(for: key)
            }
        }

        persistDiskArticleCacheIndex(force: true)
    }

    func cacheMetrics() -> CacheMetrics {
        ensureDiskArticleCacheIndexLoaded()
        let diskBytes = diskArticleCacheIndex.values.reduce(0) { $0 + $1.byteCount }
        let pinnedEntries = diskArticleCacheIndex.values.filter(\.isPinned).count
        return CacheMetrics(
            fullArticleEntries: articleCache.count,
            fullArticleBytes: articleCacheTotalBytes,
            fastArticleEntries: articleFastCache.count,
            fastArticleBytes: articleFastCacheTotalBytes,
            diskArticleEntries: diskArticleCacheIndex.count,
            diskArticleBytes: diskBytes,
            pinnedArticleEntries: pinnedEntries
        )
    }
    
    /// Clear all caches
    func clearCache() {
        searchCache.removeAll()
        summaryCache.removeAll()
        clearInMemoryArticleCache()
        clearDiskArticleCache()
        trendingCache.removeAll()
        discoverCache.removeAll()
        discoverCacheFetchedAt.removeAll()
        trendPulseCache.removeAll()
        visualContextCache.removeAll()
        peakPageviewDaysCache.removeAll()
        allTimeMostReadCache.removeAll()
        inFlightFastArticleTasks.values.forEach { $0.cancel() }
        inFlightFastArticleTasks.removeAll()
    }
}

// MARK: - String Extensions

extension String {
    func processingMetadataHTML() -> String {
        // 1. Remove style blocks, scripts, AND citations (sup tags) first
        var text = self.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: [.regularExpression, .caseInsensitive])
        // Remove citations like [1] which are usually in sup tags
        text = text.replacingOccurrences(of: "<sup[^>]*>[\\s\\S]*?</sup>", with: "", options: [.regularExpression, .caseInsensitive])
        
        // 1.5 Handle formatting (Lists, Breaks) - convert to Markdown before stripping tags
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li>", with: "\n- ", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</li>", with: "", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<ul>", with: "", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</ul>", with: "", options: .caseInsensitive)
        
        // 2. Resolve relative URLs (./Foo -> https://en.wikipedia.org/wiki/Foo)
        // Handle both " and ' quotes
        text = text.replacingOccurrences(of: "href=\"./", with: "href=\"https://en.wikipedia.org/wiki/")
        text = text.replacingOccurrences(of: "href='./", with: "href='https://en.wikipedia.org/wiki/")
        text = text.replacingOccurrences(of: "href=\"/wiki/", with: "href=\"https://en.wikipedia.org/wiki/")
        text = text.replacingOccurrences(of: "href='/wiki/", with: "href='https://en.wikipedia.org/wiki/")
        text = text.replacingOccurrences(of: "href=\"//", with: "href=\"https://")
        text = text.replacingOccurrences(of: "href='//", with: "href='https://")
        
        // 3. Remove citations [1], [a] - DONE BEFORE LINK CONVERSION
        // Doing this late risks stripping Markdown link labels like [Redpoint]
        text = text.replacingOccurrences(of: "\\[\\w+\\]", with: "", options: .regularExpression)
        
        // 4. Convert Links
        // Fix: Escape parens in URL to avoid breaking Markdown
        // Regex captures URL ($1) and Text ($2).
        do {
            let linkPattern = "<a[^>]*href=[\"']([^\"']*)[\"'][^>]*>([\\s\\S]*?)</a>"
            let regex = try NSRegularExpression(pattern: linkPattern, options: [.caseInsensitive])
            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            
            // We must iterate in reverse to avoid invalidating ranges
            let matches = regex.matches(in: text, options: [], range: nsRange).reversed()
            
            for match in matches {
                guard let urlRange = Range(match.range(at: 1), in: text),
                      let textRange = Range(match.range(at: 2), in: text),
                      let fullRange = Range(match.range, in: text) else { continue }
                
                let rawUrl = String(text[urlRange])
                let linkText = String(text[textRange])
                
                // Escape parens in URL for Markdown compatibility
                let escapedUrl = rawUrl
                    .replacingOccurrences(of: "(", with: "%28")
                    .replacingOccurrences(of: ")", with: "%29")
                
                let markdownLink = "[\(linkText)](\(escapedUrl))"
                text.replaceSubrange(fullRange, with: markdownLink)
            }
        } catch {
            wikipediaServiceLogger.error("Regex error: \(error.localizedDescription, privacy: .public)")
        }
        
        // 3. Remove remaining tags but keep content
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        
        // 5. Decode entities
        let entities = [
            "&nbsp;": " ",
            "&#160;": " ",
            "&amp;": "&",
            "&quot;": "\"",
            "&apos;": "'",
            "&lt;": "<",
            "&gt;": ">",
            "&ndash;": "-",
            "&mdash;": "—"
        ]
        
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        
        // 6. Cleanup whitespace (preserve newlines)
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        
        return text
    }
    
    /// Strip markdown links, keeping only the link text
    /// E.g. "[Passing attempts](https://...)" -> "Passing attempts"
    func strippingMarkdownLinks() -> String {
        // Pattern matches [text](url) and replaces with just text
        return self.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )
    }
}
