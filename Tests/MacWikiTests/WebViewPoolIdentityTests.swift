import Foundation
import Testing
import WebKit

@testable import MacWiki

@MainActor
struct WebViewPoolIdentityTests {
    @Test func reusableSurfaceRequiresMatchingTabTitleAndRevision() {
        let pool = WebViewPool.makeForTesting()
        let tabID = UUID()
        let revision: UInt64 = 42
        pool.resetForTesting()
        defer { pool.resetForTesting() }

        pool.store(
            WKWebView(),
            for: tabID,
            lastLoadedArticleTitle: "Reader Article",
            lastLoadedHTMLSignature: revision
        )

        #expect(
            pool.hasReusableWebView(
                for: tabID,
                articleTitle: "Reader_Article",
                contentRevision: revision
            )
        )
        #expect(
            !pool.hasReusableWebView(
                for: UUID(),
                articleTitle: "Reader Article",
                contentRevision: revision
            )
        )
        #expect(
            !pool.hasReusableWebView(
                for: tabID,
                articleTitle: "Different Article",
                contentRevision: revision
            )
        )
        #expect(
            !pool.hasReusableWebView(
                for: tabID,
                articleTitle: "Reader Article",
                contentRevision: revision + 1
            )
        )
    }

    @Test func checkoutRestoresThePreparedInspectorProjection() throws {
        let pool = WebViewPool.makeForTesting()
        let tabID = UUID()
        let webView = WKWebView()
        let projection = WebViewPool.InspectorProjection(
            tableOfContents: [
                ArticleTableOfContentsItem(id: "history", title: "History", level: 2)
            ],
            references: [],
            visibleSectionID: "history",
            hasTableOfContentsResult: true,
            hasReferencesResult: true
        )
        pool.resetForTesting()
        defer { pool.resetForTesting() }

        pool.store(
            webView,
            for: tabID,
            lastLoadedArticleTitle: "Reader Article",
            lastLoadedHTMLSignature: 42,
            inspectorProjection: projection
        )

        let checkout = try #require(pool.checkout(for: tabID))
        #expect(checkout.webView === webView)
        #expect(checkout.inspectorProjection == projection)
    }
}
