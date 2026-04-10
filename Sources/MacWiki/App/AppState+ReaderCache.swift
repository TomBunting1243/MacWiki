import Foundation

extension AppState {
    func setLiveReadingProgress(forTitle title: String, progress: Double) {
        let key = ReadStateSync.normalizedTitle(title)
        let clamped = min(max(progress, 0), 1)
        if let current = liveReadingProgressByTitle[key], abs(current - clamped) < 0.01 {
            return
        }
        liveReadingProgressByTitle[key] = clamped
    }

    func liveReadingProgress(forTitle title: String) -> Double? {
        liveReadingProgressByTitle[ReadStateSync.normalizedTitle(title)]
    }

    func setArticleHTMLPinned(_ pinned: Bool, forTitle title: String) {
        let key = ReadStateSync.normalizedTitle(title)
        if pinned {
            pinnedArticleHTMLTitles.insert(key)
        } else {
            pinnedArticleHTMLTitles.remove(key)
        }
        trimArticleHTMLCacheIfNeeded()
    }

    func cacheArticleHTML(_ html: String, forTitle title: String) {
        let key = ReadStateSync.normalizedTitle(title)
        let byteCount = html.utf8.count

        // Very large documents are expensive to retain repeatedly in-process.
        // Keep them in service/network cache paths, but skip this UI-level cache.
        if byteCount > maxArticleHTMLCacheEntryBytes {
            removeArticleHTMLCacheEntry(forKey: key)
            return
        }

        if let existingBytes = articleHTMLCacheSizeByTitle[key] {
            articleHTMLCacheTotalBytes -= existingBytes
        }

        articleHTMLCacheByTitle[key] = html
        articleHTMLCacheSizeByTitle[key] = byteCount
        articleHTMLCacheTotalBytes += byteCount
        articleHTMLCacheOrder.removeAll { $0 == key }
        articleHTMLCacheOrder.append(key)
        trimArticleHTMLCacheIfNeeded()
    }

    func cachedArticleHTML(forTitle title: String) -> String? {
        let key = ReadStateSync.normalizedTitle(title)
        guard let cached = articleHTMLCacheByTitle[key] else { return nil }
        articleHTMLCacheOrder.removeAll { $0 == key }
        articleHTMLCacheOrder.append(key)
        return cached
    }

    func trimArticleHTMLCacheIfNeeded() {
        while articleHTMLCacheOrder.count > maxArticleHTMLCacheEntries ||
              articleHTMLCacheTotalBytes > maxArticleHTMLCacheBytes {
            guard let evictKey = articleHTMLCacheOrder.first(where: { !pinnedArticleHTMLTitles.contains($0) }) ??
                    articleHTMLCacheOrder.first else { break }
            removeArticleHTMLCacheEntry(forKey: evictKey)
        }
    }

    func removeArticleHTMLCacheEntry(forKey key: String) {
        if let existingBytes = articleHTMLCacheSizeByTitle.removeValue(forKey: key) {
            articleHTMLCacheTotalBytes -= existingBytes
        }
        articleHTMLCacheByTitle.removeValue(forKey: key)
        articleHTMLCacheOrder.removeAll { $0 == key }
    }

    func resetReaderCacheState() {
        liveReadingProgressByTitle.removeAll()
        articleHTMLCacheByTitle.removeAll()
        articleHTMLCacheOrder.removeAll()
        articleHTMLCacheSizeByTitle.removeAll()
        articleHTMLCacheTotalBytes = 0
        pinnedArticleHTMLTitles.removeAll()
    }
}
