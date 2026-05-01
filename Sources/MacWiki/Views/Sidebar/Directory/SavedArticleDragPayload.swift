import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct SavedArticleDragPayload: Codable, Hashable, Transferable {
    let savedArticleID: UUID?
    let sourceListID: UUID?
    let title: String?
    let articleDescription: String?
    let extract: String?
    let thumbnailURL: URL?
    let isRead: Bool?
    let wordCount: Int?

    init(
        savedArticleID: UUID? = nil,
        sourceListID: UUID? = nil,
        title: String? = nil,
        articleDescription: String? = nil,
        extract: String? = nil,
        thumbnailURL: URL? = nil,
        isRead: Bool? = nil,
        wordCount: Int? = nil
    ) {
        self.savedArticleID = savedArticleID
        self.sourceListID = sourceListID
        self.title = title
        self.articleDescription = articleDescription
        self.extract = extract
        self.thumbnailURL = thumbnailURL
        self.isRead = isRead
        self.wordCount = wordCount
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .macWikiSavedArticleDragPayload)
    }
}

private extension UTType {
    static let macWikiSavedArticleDragPayload = UTType(exportedAs: "com.tombunting.macwiki.saved-article-drag-payload")
}
