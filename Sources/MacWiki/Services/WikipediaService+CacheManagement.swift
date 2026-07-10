import Foundation

extension WikipediaService {
    func articleByteCount(_ content: ArticleContent) -> Int {
        content.html.utf8.count
    }

    func cachedLRUValue<Value>(
        for key: String,
        in cache: [String: Value],
        order: inout LRUKeyTracker<String>
    ) -> Value? {
        guard let cached = cache[key] else { return nil }
        order.touch(key)
        return cached
    }

    func storeLRUValue<Value>(
        _ value: Value,
        for key: String,
        in cache: inout [String: Value],
        order: inout LRUKeyTracker<String>,
        maxSize: Int
    ) {
        cache[key] = value
        order.touch(key)
        trimLRUCache(&cache, order: &order, maxSize: maxSize)
    }

    func storeLRUPairedValue<Primary, Secondary>(
        primary primaryValue: Primary,
        secondary secondaryValue: Secondary,
        for key: String,
        primaryCache: inout [String: Primary],
        secondaryCache: inout [String: Secondary],
        order: inout LRUKeyTracker<String>,
        maxSize: Int
    ) {
        primaryCache[key] = primaryValue
        secondaryCache[key] = secondaryValue
        order.touch(key)
        trimPairedLRUCaches(
            primary: &primaryCache,
            secondary: &secondaryCache,
            order: &order,
            maxSize: maxSize
        )
    }

    func trimLRUCache<Value>(
        _ cache: inout [String: Value],
        order: inout LRUKeyTracker<String>,
        maxSize: Int
    ) {
        for evictedKey in order.trim(to: maxSize) {
            cache.removeValue(forKey: evictedKey)
        }
    }

    func trimPairedLRUCaches<Primary, Secondary>(
        primary: inout [String: Primary],
        secondary: inout [String: Secondary],
        order: inout LRUKeyTracker<String>,
        maxSize: Int
    ) {
        for evictedKey in order.trim(to: maxSize) {
            primary.removeValue(forKey: evictedKey)
            secondary.removeValue(forKey: evictedKey)
        }
    }

    func cachedFullArticle(for key: String) -> ArticleContent? {
        guard let cached = articleCache[key] else { return nil }
        articleCacheOrder.removeAll { $0 == key }
        articleCacheOrder.append(key)
        return cached
    }

    func cachedFastArticle(for key: String) -> ArticleContent? {
        guard let cached = articleFastCache[key] else { return nil }
        articleFastCacheOrder.removeAll { $0 == key }
        articleFastCacheOrder.append(key)
        return cached
    }

    func storeFullArticle(_ content: ArticleContent, for key: String) {
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

    func storeFastArticle(_ content: ArticleContent, for key: String) {
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

    func removeFullArticle(for key: String) {
        if let existing = articleCache.removeValue(forKey: key) {
            articleCacheTotalBytes -= articleByteCount(existing)
        }
        articleCacheOrder.removeAll { $0 == key }
    }

    func removeFastArticle(for key: String) {
        if let existing = articleFastCache.removeValue(forKey: key) {
            articleFastCacheTotalBytes -= articleByteCount(existing)
        }
        articleFastCacheOrder.removeAll { $0 == key }
    }

    func invalidateArticleCache(for key: String, preservePinnedState: Bool) {
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

    func trimFullArticleCacheIfNeeded() {
        while articleCache.count > maxArticleCacheSize || articleCacheTotalBytes > maxArticleCacheBytes {
            guard !articleCacheOrder.isEmpty else { break }
            let evictIndex = articleCacheOrder.firstIndex(where: { !pinnedArticleTitles.contains($0) }) ?? 0
            let evictedKey = articleCacheOrder.remove(at: evictIndex)
            if let evicted = articleCache.removeValue(forKey: evictedKey) {
                articleCacheTotalBytes -= articleByteCount(evicted)
            }
        }
    }

    func trimFastArticleCacheIfNeeded() {
        while articleFastCache.count > maxArticleFastCacheSize || articleFastCacheTotalBytes > maxArticleFastCacheBytes {
            guard !articleFastCacheOrder.isEmpty else { break }
            let evictIndex = articleFastCacheOrder.firstIndex(where: { !pinnedArticleTitles.contains($0) }) ?? 0
            let evictedKey = articleFastCacheOrder.remove(at: evictIndex)
            if let evicted = articleFastCache.removeValue(forKey: evictedKey) {
                articleFastCacheTotalBytes -= articleByteCount(evicted)
            }
        }
    }

    func ensureDiskArticleCacheIndexLoaded() {
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

    func persistDiskArticleCacheIndex(force: Bool = false) {
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

    func diskArticleFileURL(fileName: String) -> URL? {
        diskArticleCacheDirectoryURL?.appendingPathComponent(fileName)
    }

    func stableHash(for key: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }

    func diskArticleFileName(for key: String) -> String {
        let hash = stableHash(for: key)
        return "article-\(String(hash, radix: 16)).json"
    }

    func storeDiskArticle(_ content: ArticleContent, for key: String, pinned: Bool) {
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
            wikipediaServiceLogger.error("Disk article cache write failed: \(error.localizedDescription, privacy: .public)")
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

    func storeDiskArticleSizeAware(_ content: ArticleContent, for key: String, pinned: Bool) {
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

    func startDeferredDiskStoreWorkerIfNeeded() {
        guard deferredDiskStoreWorkerTask == nil else { return }

        deferredDiskStoreWorkerTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await self.runDeferredDiskStoreWorker()
        }
    }

    func runDeferredDiskStoreWorker() async {
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

    func loadDiskArticle(for key: String) -> ArticleContent? {
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

    func removeDiskArticle(for key: String) {
        guard let entry = diskArticleCacheIndex.removeValue(forKey: key) else { return }
        if entry.isPinned {
            pinnedArticleTitles.remove(key)
        }
        if let fileURL = diskArticleFileURL(fileName: entry.fileName) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    func evictDiskArticlesIfNeeded() {
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

    func clearInFlightPageMetadataTask(for normalizedTitle: String) {
        inFlightPageMetadataTasks.removeValue(forKey: normalizedTitle)
    }

    func clearInFlightFirstRevisionDateTask(for normalizedTitle: String) {
        inFlightFirstRevisionDateTasks.removeValue(forKey: normalizedTitle)
    }

    func clearInFlightSummaryTask(for normalizedTitle: String) {
        inFlightSummaryTasks.removeValue(forKey: normalizedTitle)
    }

    func storePageMetadata(_ metadata: PageMetadata, for normalizedTitle: String) {
        storeLRUValue(
            metadata,
            for: normalizedTitle,
            in: &pageMetadataCache,
            order: &pageMetadataCacheOrder,
            maxSize: maxPageMetadataCacheSize
        )
    }

    func setArticlePinned(_ title: String, pinned: Bool) {
        let key = normalizedArticleTitle(title)
        // Load persisted pins before applying the requested mutation. Loading after
        // this point replaces `pinnedArticleTitles` and can silently discard the
        // first pin change made during a service lifetime.
        ensureDiskArticleCacheIndexLoaded()

        if pinned {
            pinnedArticleTitles.insert(key)
        } else {
            pinnedArticleTitles.remove(key)
        }

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
        pageMetadataCacheOrder.removeAll()
        trendPulseCache.removeAll()
        trendPulseCacheOrder.removeAll()
        firstRevisionDateCache.removeAll()
        firstRevisionDateCacheOrder.removeAll()
        visualContextCache.removeAll()
        visualContextCacheOrder.removeAll()
        peakPageviewDaysCache.removeAll()
        peakPageviewDaysCacheOrder.removeAll()
        inFlightSummaryTasks.values.forEach { $0.cancel() }
        inFlightSummaryTasks.removeAll()
        inFlightPageMetadataTasks.values.forEach { $0.cancel() }
        inFlightPageMetadataTasks.removeAll()
        inFlightFirstRevisionDateTasks.values.forEach { $0.cancel() }
        inFlightFirstRevisionDateTasks.removeAll()
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
        searchCacheOrder.removeAll()
        summaryCache.removeAll()
        summaryCacheOrder.removeAll()
        clearInMemoryArticleCache()
        clearDiskArticleCache()
        trendingCache.removeAll()
        trendingCacheOrder.removeAll()
        discoverCache.removeAll()
        discoverCacheFetchedAt.removeAll()
        discoverCacheOrder.removeAll()
        trendPulseCache.removeAll()
        trendPulseCacheOrder.removeAll()
        visualContextCache.removeAll()
        visualContextCacheOrder.removeAll()
        peakPageviewDaysCache.removeAll()
        peakPageviewDaysCacheOrder.removeAll()
        allTimeMostReadCache.removeAll()
        allTimeMostReadCacheOrder.removeAll()
        inFlightFastArticleTasks.values.forEach { $0.cancel() }
        inFlightFastArticleTasks.removeAll()
    }
}
