import Foundation
import SwiftData

// MARK: - Enums

/// How articles are sorted within a reading list
enum ListSortMode: String, Codable, CaseIterable {
    case addedDate = "Date Added"
    case manual = "Manual"
    case title = "Title"
    case articleLength = "Article Length"
}

/// Filter mode for viewing articles in a list
enum ListFilterMode: String, Codable, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case read = "Read"
}

// MARK: - ReadingList

/// A user-created reading list for saving Wikipedia articles
@Model
final class ReadingList {
    var id: UUID
    var name: String
    var icon: String  // SF Symbol name
    @Relationship(deleteRule: .cascade) var articles: [SavedArticle] = []
    var createdAt: Date
    var updatedAt: Date
    
    // Sorting & Filtering preferences (persist per list)
    var sortModeRaw: String = ListSortMode.addedDate.rawValue
    var filterModeRaw: String = ListFilterMode.all.rawValue
    
    // For manual ordering in sidebar
    var sortOrder: Int = 0
    
    // Area/folder reference (nil = root level)
    var areaId: UUID?
    
    var sortMode: ListSortMode {
        get { ListSortMode(rawValue: sortModeRaw) ?? .addedDate }
        set { sortModeRaw = newValue.rawValue }
    }
    
    var filterMode: ListFilterMode {
        get { ListFilterMode(rawValue: filterModeRaw) ?? .all }
        set { filterModeRaw = newValue.rawValue }
    }
    
    init(name: String, icon: String = "bookmark.fill") {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - SavedArticle

/// An article saved to a reading list
@Model
final class SavedArticle {
    var id: UUID
    var title: String
    var articleDescription: String?
    var extract: String?  // Article preview/excerpt
    var thumbnailURLString: String?
    var savedAt: Date
    var readingList: ReadingList?

    // Read/unread status
    var isRead: Bool = false

    // For manual ordering within list
    var manualOrder: Int = 0

    // Label reference (optional - article can have no label)
    var labelId: UUID?
    
    // Accurate word count
    var wordCount: Int?

    var thumbnailURL: URL? {
        guard let urlString = thumbnailURLString else { return nil }
        return URL(string: urlString)
    }

    /// Approximate article length based on extract (used for sorting)
    /// Favors accurate word count if available
    var approximateLength: Int {
        if let wc = wordCount { return wc }
        return extract?.count ?? 0
    }

    init(title: String, description: String? = nil, extract: String? = nil, thumbnailURL: URL? = nil, list: ReadingList? = nil, wordCount: Int? = nil) {
        self.id = UUID()
        self.title = title
        self.articleDescription = description
        self.extract = extract
        self.thumbnailURLString = thumbnailURL?.absoluteString
        self.savedAt = Date()
        self.readingList = list
        self.wordCount = wordCount
    }
}
