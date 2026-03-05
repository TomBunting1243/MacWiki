import Foundation
import SwiftData
import SwiftUI

// MARK: - LabelColor Enum

/// Predefined label colors matching system palette
enum LabelColor: String, CaseIterable, Codable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case purple = "Purple"
    case pink = "Pink"
    case gray = "Gray"

    /// SwiftUI Color representation
    var swiftUIColor: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .gray: return .gray
        }
    }

    /// Opacity for row highlight mode
    var highlightOpacity: Double { 0.12 }
}

// MARK: - LabelDisplayMode Enum

/// How labels are visually displayed on article rows
enum LabelDisplayMode: String, CaseIterable {
    case coloredDot = "Colored Dot"
    case rowHighlight = "Row Highlight"

    var description: String {
        switch self {
        case .coloredDot:
            return "Color the unread indicator"
        case .rowHighlight:
            return "Highlight the entire row"
        }
    }
}

// MARK: - Label Model

/// A user-created label for categorizing saved articles
@Model
final class Label: Identifiable {
    var id: UUID
    var name: String
    var colorRaw: String  // Store enum as String (existing pattern)
    var sortOrder: Int = 0
    var createdAt: Date

    /// Computed property for type-safe color access
    var color: LabelColor {
        get { LabelColor(rawValue: colorRaw) ?? .blue }
        set { colorRaw = newValue.rawValue }
    }

    init(name: String, color: LabelColor = .blue) {
        self.id = UUID()
        self.name = name
        self.colorRaw = color.rawValue
        self.createdAt = Date()
    }
}
