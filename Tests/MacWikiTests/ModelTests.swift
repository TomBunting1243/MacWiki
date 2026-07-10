import Foundation
import Testing

@testable import MacWiki

@Test func readingListNamePolicyTrimsNamesAndRejectsWhitespaceOnlyInput() {
    #expect(ReadingListNamePolicy.normalized("  Research Queue\n") == "Research Queue")
    #expect(ReadingListNamePolicy.normalized(" \t\n ") == nil)
}

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

@MainActor
@Test func articleLookupIndexBuildsSavedTitleMembershipFromReadingLists() {
    let list = ReadingList(name: "Inbox")
    let saved = SavedArticle(title: "A/B testing?", list: list)
    list.articles.append(saved)

    let index = ArticleLookupIndex(readingLists: [list])

    #expect(index.isSaved(title: "A/B testing?"))
    #expect(index.savedArticle(for: "A/B testing?")?.id == saved.id)
}

@MainActor
@Test func articleLookupIndexPrefersArticleStateForEffectiveReadState() {
    let saved = SavedArticle(title: "AC/DC")
    saved.isRead = false

    let state = ArticleState(
        articleTitle: "AC/DC",
        articleURL: URL(string: WikipediaURLBuilder.articleURLString(forTitle: "AC/DC"))!,
        isRead: true,
        readingProgress: 0.42
    )

    let index = ArticleLookupIndex(
        articleStates: [state],
        savedArticles: [saved]
    )

    #expect(index.articleState(for: "AC/DC")?.id == state.id)
    #expect(index.effectiveReadState(for: "AC/DC", fallback: false))
}

@MainActor
@Test func stableTagFingerprintChangesWhenTagIdentityChangesAtSameCount() {
    let firstTag = Tag(name: "Alpha")
    let secondTag = Tag(name: "Beta")

    #expect(
        stableTagFingerprint(for: [firstTag]) !=
        stableTagFingerprint(for: [secondTag])
    )
}

@MainActor
@Test func articleLookupIndexFingerprintChangesWhenArticleStateTagsChangeAtSameCount() {
    let articleURL = URL(string: WikipediaURLBuilder.articleURLString(forTitle: "AC/DC"))!
    let state = ArticleState(articleTitle: "AC/DC", articleURL: articleURL)
    let readingList = ReadingList(name: "Inbox")

    state.tags = [Tag(name: "Alpha")]
    let directFingerprintBefore = articleLookupIndexFingerprint(
        articleStates: [state],
        savedArticles: []
    )
    let readingListsFingerprintBefore = articleLookupIndexFingerprint(
        articleStates: [state],
        readingLists: [readingList]
    )

    state.tags = [Tag(name: "Beta")]
    let directFingerprintAfter = articleLookupIndexFingerprint(
        articleStates: [state],
        savedArticles: []
    )
    let readingListsFingerprintAfter = articleLookupIndexFingerprint(
        articleStates: [state],
        readingLists: [readingList]
    )

    #expect(directFingerprintBefore != directFingerprintAfter)
    #expect(readingListsFingerprintBefore != readingListsFingerprintAfter)
}
