import Foundation
import Testing
import WebKit

@testable import MacWiki

@MainActor
struct WebViewPoolIdentityTests {
    @Test func reusableSurfaceRequiresMatchingTabTitleAndRevision() {
        let pool = WebViewPool.shared
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
}
