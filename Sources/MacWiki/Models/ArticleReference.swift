import Foundation

struct ArticleReferenceSection: Identifiable, Hashable {
    let id: String
    let title: String
    var items: [ArticleReferenceItem]
}

struct ArticleReferenceItem: Identifiable, Hashable {
    let id: String
    let label: String?
    let text: String
    let html: String?
    let links: [String]
    let group: String?
}
