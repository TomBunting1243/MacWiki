import Foundation
import SwiftData
import SwiftUI

/// Represents a text highlight with robust anchoring for article versioning
@Model
final class Highlight {
    var id: UUID

    /// The exact highlighted text
    var text: String

    /// Optional user note attached to this highlight
    var note: String?

    /// Tags attached to this highlight (multi-select)
    var tags: [Tag] = []

    /// Highlight color (stored as raw value)
    var colorRaw: String

    /// Article title (used as identifier)
    var articleTitle: String

    /// Wikipedia revision ID when highlight was created (for version tracking)
    var articleRevisionId: Int?

    // MARK: - Anchoring Strategy
    // Multiple anchors for resilient highlight positioning

    /// Primary: XPath-like selector to the container element
    /// e.g., "section[2]/p[3]" means 2nd section, 3rd paragraph
    var elementPath: String?

    /// Text offset within the element (character position)
    var startOffset: Int

    /// Length of the highlight in characters
    var length: Int

    /// Context: 50 chars before the highlight (for fuzzy matching)
    var contextBefore: String?

    /// Context: 50 chars after the highlight (for fuzzy matching)
    var contextAfter: String?

    /// Section title where highlight appears (e.g., "Early life")
    var sectionTitle: String?

    /// True when highlight cannot be restored due to article text changes
    /// Optional for lightweight migration; defaults to false in computed accessor.
    var isStaleRaw: Bool?

    /// True when a highlight has been archived from active notes/rehydration flows.
    /// Optional for lightweight migration; defaults to false in computed accessor.
    var isArchivedRaw: Bool?

    // MARK: - Sync Status (for future Readwise integration)

    /// Readwise highlight ID (nil if not synced)
    var readwiseId: String?

    /// Sync status for offline support
    var syncStatusRaw: String

    // MARK: - Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Properties

    var color: HighlightColor {
        get { HighlightColor(rawValue: colorRaw) ?? .yellow }
        set { colorRaw = newValue.rawValue }
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .local }
        set { syncStatusRaw = newValue.rawValue }
    }

    var isStale: Bool {
        get { isStaleRaw ?? false }
        set { isStaleRaw = newValue }
    }

    var isArchived: Bool {
        get { isArchivedRaw ?? false }
        set { isArchivedRaw = newValue }
    }

    init(
        text: String,
        articleTitle: String,
        elementPath: String? = nil,
        startOffset: Int,
        length: Int,
        contextBefore: String? = nil,
        contextAfter: String? = nil,
        sectionTitle: String? = nil,
        color: HighlightColor = .yellow
    ) {
        self.id = UUID()
        self.text = text
        self.articleTitle = articleTitle
        self.elementPath = elementPath
        self.startOffset = startOffset
        self.length = length
        self.contextBefore = contextBefore
        self.contextAfter = contextAfter
        self.sectionTitle = sectionTitle
        self.colorRaw = color.rawValue
        self.isStaleRaw = false
        self.isArchivedRaw = false
        self.syncStatusRaw = SyncStatus.local.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Available highlight colors - optimized for both light and dark modes
enum HighlightColor: String, CaseIterable, Codable {
    case yellow = "Yellow"
    case blue = "Blue"
    case pink = "Pink"
    case orange = "Orange"

    /// CSS color value for rendering in WebView (works in both light/dark modes)
    var cssColor: String {
        switch self {
        case .yellow: return "rgba(255, 213, 0, 0.28)"   // Softer opacity for text legibility
        case .blue: return "rgba(59, 130, 246, 0.26)"    // Tailwind blue-500, softened
        case .pink: return "rgba(236, 72, 153, 0.26)"    // Tailwind pink-500, softened
        case .orange: return "rgba(249, 115, 22, 0.28)"  // Tailwind orange-500, softened
        }
    }

    /// SwiftUI color for UI elements (toolbar, inspector)
    var swiftUIColor: Color {
        switch self {
        case .yellow: return Color(red: 1.0, green: 0.84, blue: 0.0)   // Matches CSS
        case .blue: return Color(red: 0.23, green: 0.51, blue: 0.96)   // Matches CSS
        case .pink: return Color(red: 0.93, green: 0.28, blue: 0.60)   // Matches CSS
        case .orange: return Color(red: 0.98, green: 0.45, blue: 0.09) // Matches CSS
        }
    }

    /// Darker variant for borders/accents
    var accentColor: Color {
        switch self {
        case .yellow: return Color(red: 0.85, green: 0.65, blue: 0.0)
        case .blue: return Color(red: 0.15, green: 0.39, blue: 0.85)
        case .pink: return Color(red: 0.83, green: 0.18, blue: 0.50)
        case .orange: return Color(red: 0.88, green: 0.35, blue: 0.0)
        }
    }

    /// SF Symbol for color picker
    var iconName: String {
        "circle.fill"
    }
}

/// Sync status for Readwise integration
enum SyncStatus: String, Codable {
    case local = "local"              // Only exists locally
    case synced = "synced"            // Synced with Readwise
    case pendingUpload = "pending_upload"
    case pendingUpdate = "pending_update"
    case pendingDelete = "pending_delete"
    case error = "error"
}

/// Represents a standalone note on an article (not attached to highlight)
@Model
final class ArticleNote {
    var id: UUID

    /// Note content (supports markdown)
    var content: String

    /// Article title
    var articleTitle: String

    /// Optional element path if note is anchored to specific location
    var elementPath: String?

    var createdAt: Date
    var updatedAt: Date

    init(content: String, articleTitle: String, elementPath: String? = nil) {
        self.id = UUID()
        self.content = content
        self.articleTitle = articleTitle
        self.elementPath = elementPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
