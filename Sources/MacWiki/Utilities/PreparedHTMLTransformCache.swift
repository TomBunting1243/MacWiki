import Foundation

struct PreparedHTMLTransformCache {
    enum Entry: Equatable {
        case passthrough
        case rewritten(String)

        var byteCost: Int {
            switch self {
            case .passthrough:
                return 0
            case .rewritten(let html):
                return html.utf8.count
            }
        }
    }

    private var entries: [String: Entry] = [:]
    private var order = LRUKeyTracker<String>()
    private(set) var totalBytes = 0

    private let maxEntries: Int
    private let maxTotalBytes: Int
    private let maxEntryBytes: Int

    init(
        maxEntries: Int = 4,
        maxTotalBytes: Int = 2_400_000,
        maxEntryBytes: Int = 1_200_000
    ) {
        self.maxEntries = max(1, maxEntries)
        self.maxTotalBytes = max(0, maxTotalBytes)
        self.maxEntryBytes = max(0, maxEntryBytes)
    }

    mutating func cachedEntry(forKey key: String) -> Entry? {
        guard let entry = entries[key] else { return nil }
        order.touch(key)
        return entry
    }

    mutating func store(_ entry: Entry, forKey key: String) {
        if case .rewritten = entry, entry.byteCost > maxEntryBytes {
            removeValue(forKey: key)
            return
        }

        if let existing = entries[key] {
            totalBytes -= existing.byteCost
        }

        entries[key] = entry
        totalBytes += entry.byteCost
        order.touch(key)
        trimIfNeeded()
    }

    private mutating func trimIfNeeded() {
        while entries.count > maxEntries || totalBytes > maxTotalBytes {
            guard let oldestKey = order.orderedKeys.first else { break }
            removeValue(forKey: oldestKey)
        }
    }

    private mutating func removeValue(forKey key: String) {
        if let existing = entries.removeValue(forKey: key) {
            totalBytes -= existing.byteCost
        }
        order.remove(key)
    }
}
