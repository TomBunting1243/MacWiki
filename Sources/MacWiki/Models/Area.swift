import Foundation
import SwiftData

/// A folder/area for organizing reading lists hierarchically
@Model
final class Area {
    var id: UUID
    var name: String
    var icon: String  // SF Symbol name
    var parentId: UUID?  // For nesting (nil = root level)
    var isExpanded: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date
    
    init(name: String, icon: String = "folder.fill", parentId: UUID? = nil) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.parentId = parentId
        self.createdAt = Date()
    }
}
