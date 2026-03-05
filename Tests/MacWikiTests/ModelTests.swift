import Foundation
import Testing

@testable import MacWiki

@Test func articleCreation() {
    let article = Article(
        id: "12345",
        title: "Swift (programming language)",
        description: "A general-purpose programming language"
    )
    
    #expect(article.id == "12345")
    #expect(article.title == "Swift (programming language)")
    #expect(article.url.absoluteString.contains("Swift"))
}

@Test func readingListManagement() {
    let list = ReadingList(name: "Research", icon: "book")
    
    #expect(list.name == "Research")
    #expect(list.icon == "book")
    #expect(list.articles.isEmpty)
    
    let savedArticle = SavedArticle(title: "Test Article")
    list.articles.append(savedArticle)
    
    #expect(list.articles.count == 1)
    #expect(list.articles.first?.title == "Test Article")
}

@Test func highlightCreation() {
    let highlight = Highlight(
        text: "This is important text",
        articleTitle: "Test Article",
        elementPath: "section[1]/p[1]",
        startOffset: 1234,
        length: 22
    )
    
    #expect(highlight.text == "This is important text")
    #expect(highlight.articleTitle == "Test Article")
    #expect(highlight.startOffset == 1234)
    #expect(highlight.color == HighlightColor.yellow)
    #expect(highlight.readwiseId == nil)
}

@Test func wikipediaURLBuilderEncodesReservedCharacters() {
    let encoded = WikipediaURLBuilder.articleURLString(forTitle: "A/B testing?")
    #expect(encoded == "https://en.wikipedia.org/wiki/A%2FB_testing%3F")
}

@Test func articleURLUsesCanonicalWikipediaEncoding() {
    let article = Article(id: "slash", title: "AC/DC")
    #expect(article.url.absoluteString == "https://en.wikipedia.org/wiki/AC%2FDC")
}

@MainActor
@Test func readStateURLStringUsesCanonicalWikipediaEncoding() {
    #expect(
        ReadStateSync.urlString(for: "A/B testing?") ==
        "https://en.wikipedia.org/wiki/A%2FB_testing%3F"
    )
}

@Test func articleEncodingOmitsHTMLContentFromPersistencePayload() throws {
    let article = Article(
        id: "html",
        title: "Swift",
        description: "Language",
        extract: "A language",
        htmlContent: "<html>heavy payload</html>"
    )

    let data = try JSONEncoder().encode(article)
    let payload = String(decoding: data, as: UTF8.self)

    #expect(!payload.contains("htmlContent"))
    #expect(payload.contains("\"title\":\"Swift\""))
}

@MainActor
@Test func searchCoordinatorDefaultDebounceMatchesRepoContract() {
    #expect(SearchCoordinator.defaultDebounceMilliseconds == 300)
}
