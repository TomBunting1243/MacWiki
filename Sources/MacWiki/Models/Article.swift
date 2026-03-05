import Foundation

/// Represents a Wikipedia article
struct Article: Identifiable, Hashable, Codable {
    private static let fallbackURL: URL = {
        URL(string: "https://en.wikipedia.org/wiki/") ?? URL(fileURLWithPath: "/")
    }()

    /// Unique identifier (typically the page ID from Wikipedia)
    let id: String

    /// Article title
    let title: String

    /// Short description/subtitle
    var description: String?

    /// Article extract/preview text
    var extract: String?

    /// URL to the article thumbnail image
    var thumbnailURL: URL?

    /// Full HTML content (loaded on demand)
    var htmlContent: String?

    /// Article URL on Wikipedia
    var url: URL {
        WikipediaURLBuilder.articleURL(forTitle: title) ?? Self.fallbackURL
    }

    /// When this article was last opened
    var lastOpened: Date?

    /// Whether the user has marked this as read
    var isRead: Bool = false

    /// Estimated word count of the full article
    var wordCount: Int?

    // Custom decoder to handle missing fields from old persisted data
    enum CodingKeys: String, CodingKey {
        case id, title, description, extract, thumbnailURL, lastOpened, isRead, wordCount
    }

    init(id: String, title: String, description: String? = nil, extract: String? = nil, thumbnailURL: URL? = nil, htmlContent: String? = nil, lastOpened: Date? = nil, isRead: Bool = false, wordCount: Int? = nil) {
        self.id = id
        self.title = title
        self.description = description
        self.extract = extract
        self.thumbnailURL = thumbnailURL
        self.htmlContent = htmlContent
        self.lastOpened = lastOpened
        self.isRead = isRead
        self.wordCount = wordCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        extract = try container.decodeIfPresent(String.self, forKey: .extract)
        thumbnailURL = try container.decodeIfPresent(URL.self, forKey: .thumbnailURL)
        // Session persistence intentionally omits full HTML payloads to keep launch restore light.
        htmlContent = nil
        lastOpened = try container.decodeIfPresent(Date.self, forKey: .lastOpened)
        isRead = try container.decodeIfPresent(Bool.self, forKey: .isRead) ?? false
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount)
    }
}
