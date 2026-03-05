import Foundation
import SwiftData

/// A user-created tag for categorizing highlights across articles
@Model
final class Tag: Identifiable {
    var id: UUID
    var name: String
    var sortOrder: Int = 0
    var createdAt: Date

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
