import Foundation
import Testing

@testable import MacWiki

@MainActor
struct ReferenceListHelpersTests {
    @Test func buildsGoogleSearchFallbackForReferencesWithoutLinks() {
        let item = ArticleReferenceItem(
            id: "book",
            label: nil,
            text: "[1] Jane Smith. The Example Book. Example Press, 2025.",
            html: nil,
            links: [],
            group: nil
        )

        let url = ReferenceListHelpers.fallbackSearchURL(for: item)

        #expect(url?.host == "www.google.com")
        #expect(url?.path == "/search")
        #expect(url?.query?.contains("The%20Example%20Book") == true)
        #expect(ReferenceListHelpers.canOpen(item))
    }

    @Test func ignoresWikipediaIdentifierUtilityLinksForFallbackSearch() {
        let item = ArticleReferenceItem(
            id: "isbn",
            label: nil,
            text: "[1] Jane Smith. The Example Book. Example Press, 2025.",
            html: nil,
            links: ["https://en.wikipedia.org/wiki/ISBN_(identifier)"],
            group: nil
        )
        var openedURL: URL?

        ReferenceListHelpers.openFirstLink(
            appState: AppState(),
            item: item
        ) { url in
            openedURL = url
        }

        #expect(openedURL?.host == "www.google.com")
        #expect(openedURL?.path == "/search")
    }

    @Test func hidesCssReferenceRowsFromVisibleSections() {
        let cssLeak = ArticleReferenceItem(
            id: "css",
            label: "1",
            text: #".mw-parser-output cite.citation{font-style:inherit}.cs1-ws-icon a{background:url("//upload.wikimedia.org/icon.svg")}"#,
            html: nil,
            links: [],
            group: nil
        )
        let realReference = ArticleReferenceItem(
            id: "real",
            label: "2",
            text: "Jane Smith. The Example Book. Example Press, 2025.",
            html: nil,
            links: [],
            group: nil
        )

        let visible = ReferenceListHelpers.visibleSections(
            from: [ArticleReferenceSection(id: "refs", title: "References", items: [cssLeak, realReference])]
        )

        #expect(visible.flatMap(\.items).map(\.id) == ["real"])
    }

    @Test func prefersExistingValidLinksOverFallbackSearch() {
        let item = ArticleReferenceItem(
            id: "web",
            label: "2",
            text: "Example source",
            html: nil,
            links: ["not a url", "https://example.com/source"],
            group: nil
        )
        var openedURL: URL?

        ReferenceListHelpers.openFirstLink(
            appState: AppState(),
            item: item
        ) { url in
            openedURL = url
        }

        #expect(openedURL == URL(string: "https://example.com/source"))
    }
}
