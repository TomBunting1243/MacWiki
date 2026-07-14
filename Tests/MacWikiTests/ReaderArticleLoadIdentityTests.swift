import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ReaderArticleLoadIdentityTests {
    @Test func identityStopsAnOutgoingArticleFromPublishingIntoTheReplacement() throws {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "article-a", title: "Article A"))
        let tabID = try #require(store.activeTabId)
        let outgoing = ReaderArticleLoadIdentity(tabID: tabID, articleID: "article-a")

        #expect(outgoing.matches(store.activeReaderProjection))

        _ = store.openArticle(Article(id: "article-b", title: "Article B"))

        #expect(!outgoing.matches(store.activeReaderProjection))
        #expect(store.activeReaderProjection.activeTabID == tabID)
        #expect(store.activeReaderProjection.article?.id == "article-b")
    }

    @Test func identityRequiresTheOriginatingTabAsWellAsTheArticle() throws {
        let store = TabSessionStore(persistenceMode: .ephemeral)
        _ = store.openArticle(Article(id: "shared", title: "Shared"))
        let firstTabID = try #require(store.activeTabId)
        let request = ReaderArticleLoadIdentity(tabID: firstTabID, articleID: "shared")

        _ = store.openArticle(
            Article(id: "shared", title: "Shared"),
            inNewTab: true
        )

        #expect(!request.matches(store.activeReaderProjection))
        #expect(store.activeReaderProjection.activeTabID != firstTabID)
        #expect(store.activeReaderProjection.article?.id == "shared")
    }
}
