import Foundation
import SwiftData

/// Per-article state not tied to reading lists (read status, labels, etc.)
@Model
final class ArticleState {
    var id: UUID
    var articleTitle: String
    var articleURLString: String
    var isRead: Bool
    /// Reading progress from 0.0 - 1.0 (nil when unknown)
    var readingProgress: Double?
    var labelId: UUID?
    var tags: [Tag] = []
    var createdAt: Date
    var updatedAt: Date

    var articleURL: URL? {
        URL(string: articleURLString)
    }

    init(articleTitle: String, articleURL: URL, isRead: Bool = false, readingProgress: Double? = nil, labelId: UUID? = nil) {
        self.id = UUID()
        self.articleTitle = articleTitle
        self.articleURLString = articleURL.absoluteString
        self.isRead = isRead
        self.readingProgress = readingProgress
        self.labelId = labelId
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
