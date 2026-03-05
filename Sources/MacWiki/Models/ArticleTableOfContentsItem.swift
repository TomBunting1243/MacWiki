import Foundation

struct ArticleTableOfContentsItem: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let level: Int
}
