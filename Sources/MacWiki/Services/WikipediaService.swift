import Foundation
import os

let wikipediaServiceLogger = Logger(subsystem: "com.macwiki", category: "wikipedia-service")

/// Service for interacting with the Wikipedia API
///
/// Provides search, article content, and summary fetching capabilities
/// with built-in caching and request management.
actor WikipediaService {
    static let shared = WikipediaService()

    typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias RetrySleeper = @Sendable (Duration) async throws -> Void

    // MARK: - Types

    struct DiskArticlePayload: Codable {
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

    struct DiskArticleIndexEnvelope: Codable {
        let version: Int
        var entries: [String: DiskArticleIndexEntry]
    }

    struct DiskArticleIndexEntry: Codable {
        var fileName: String
        var byteCount: Int
        var lastAccessedAt: TimeInterval
        var isPinned: Bool
    }

    struct DeferredDiskStorePayload: Sendable {
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
        fileManager: FileManager = .default,
        requestLoader: RequestLoader? = nil,
        retrySleeper: RetrySleeper? = nil
    ) {
        self.fileManager = fileManager

        if let requestLoader {
            self.requestLoader = requestLoader
        } else {
            let session = Self.makeDefaultURLSession()
            self.requestLoader = { request in
                try await session.data(for: request)
            }
        }
        self.retrySleeper = retrySleeper ?? { duration in
            try await Task.sleep(for: duration)
        }

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

    private static func makeDefaultURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 18
        configuration.timeoutIntervalForResource = 24
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
    // MARK: - Article Content

    /// Fetch full article content as mobile-html
    /// - Parameter title: The article title
    struct ArticleSummary: Sendable {
        let title: String
        let description: String?
        let extract: String?
        let thumbnailURL: URL?
        let thumbnailPixelSize: CGSize?
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

    let baseURL = "https://en.wikipedia.org"
    // Falls back to the current beta version when running as a bare SwiftPM
    // executable, where Bundle.main carries no Info.plist.
    let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.0"
        return "MacWiki/\(version) (https://github.com/tombunting/MacWiki)"
    }()
    let fileManager: FileManager
    let requestLoader: RequestLoader
    let retrySleeper: RetrySleeper

    // MARK: - Caching

    var searchCache: [String: [SearchResult]] = [:]
    var searchCacheOrder = LRUKeyTracker<String>()
    var summaryCache: [String: ArticleSummary] = [:]
    var summaryCacheOrder = LRUKeyTracker<String>()
    var articleCache: [String: ArticleContent] = [:]
    var articleFastCache: [String: ArticleContent] = [:]
    var inFlightSummaryTasks: [String: Task<ArticleSummary, Error>] = [:]
    var inFlightFastArticleTasks: [String: Task<(content: ArticleContent, source: FastArticleSource), Error>] = [:]
    var inFlightPageMetadataTasks: [String: Task<PageMetadata, Error>] = [:]
    var deferredDiskStorePayloadByKey: [String: DeferredDiskStorePayload] = [:]
    var deferredDiskStoreWorkerTask: Task<Void, Never>?
    var articleCacheOrder: [String] = []
    var articleFastCacheOrder: [String] = []
    var articleCacheTotalBytes: Int = 0
    var articleFastCacheTotalBytes: Int = 0
    var trendingCache: [String: [SearchResult]] = [:]
    var trendingCacheOrder = LRUKeyTracker<String>()
    var discoverCache: [String: DiscoverFeed] = [:]
    var discoverCacheFetchedAt: [String: Date] = [:]
    var discoverCacheOrder = LRUKeyTracker<String>()
    var pageMetadataCache: [String: PageMetadata] = [:]
    var pageMetadataCacheOrder = LRUKeyTracker<String>()
    var trendPulseCache: [String: TrendPulse] = [:]
    var trendPulseCacheOrder = LRUKeyTracker<String>()
    var firstRevisionDateCache: [String: Date] = [:]
    var firstRevisionDateCacheOrder = LRUKeyTracker<String>()
    var inFlightFirstRevisionDateTasks: [String: Task<Date?, Never>] = [:]
    var visualContextCache: [String: [VisualContextImage]] = [:]
    var visualContextCacheOrder = LRUKeyTracker<String>()
    var peakPageviewDaysCache: [String: [PeakPageviewDay]] = [:]
    var peakPageviewDaysCacheOrder = LRUKeyTracker<String>()
    var allTimeMostReadCache: [String: [AllTimeMostReadEntry]] = [:]
    var allTimeMostReadCacheOrder = LRUKeyTracker<String>()
    var pinnedArticleTitles: Set<String> = []

    let diskArticleCacheDirectoryURL: URL?
    let diskArticleCacheIndexURL: URL?
    var diskArticleCacheIndex: [String: DiskArticleIndexEntry] = [:]
    var didLoadDiskArticleCacheIndex = false
    var lastDiskIndexPersistAt: TimeInterval = 0

    let maxSearchCacheSize = 100
    let maxSummaryCacheSize = 100
    let maxArticleCacheSize = 12
    let maxArticleFastCacheSize = 10
    let maxArticleCacheBytes = 9_000_000
    let maxArticleFastCacheBytes = 7_000_000
    let maxCachedArticleHTMLBytes = 900_000
    let maxDiskCachedArticleHTMLBytes = 1_500_000
    let deferredDiskStoreThresholdBytes = 420_000
    let deferredDiskStoreInitialDelayNs: UInt64 = 140_000_000
    let deferredDiskStoreInterItemDelayNs: UInt64 = 30_000_000
    let maxDiskArticleCacheEntries = 300
    let maxDiskArticleCacheBytes = 220_000_000
    let diskIndexTouchPersistInterval: TimeInterval = 30
    let diskArticleCacheVersion = 1
    let fastPathWordCountExactScanBytes = 420_000
    let fastPathWordCountSampleBytes = 220_000
    let maxTrendingCacheSize = 14
    let maxDiscoverCacheSize = 14
    let discoverTodayCacheTTL: TimeInterval = 15 * 60
    let maxPageMetadataCacheSize = 240
    let maxTrendPulseCacheSize = 240
    let maxFirstRevisionDateCacheSize = 240
    let maxVisualContextCacheSize = 120
    let maxPeakPageviewCacheSize = 180
    let maxAllTimeMostReadCacheSize = 8
    let maxInfoboxScanWindow = 220_000
    let maxInfoboxRows = 120
    let maxInfoboxMetadataItems = 80

    let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    let iso8601FractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    let featuredFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    let onThisDayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    let pageviewsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter
    }()

    let urlPathAllowedNoSlash: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return allowed
    }()

    let featuredFeedDisplayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.timeStyle = .none
        formatter.dateStyle = .long
        return formatter
    }()

    // MARK: - Search

    /// Search Wikipedia for articles matching a query
    /// - Parameter query: The search term
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
        return self.replacingOccurrences(
            of: "\\[([^\\]]+)\\]\\([^)]+\\)",
            with: "$1",
            options: .regularExpression
        )
    }
}
