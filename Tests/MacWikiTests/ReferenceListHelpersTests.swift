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
            appState: AppState(persistenceMode: .ephemeral),
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

    @Test func presentationSanitizesInputOnceAndRetainsRowCountAndIdentity() {
        let cssLeak = ArticleReferenceItem(
            id: "css",
            label: "1",
            text: #".mw-parser-output cite.citation{font-style:inherit}.cs1-ws-icon a{background:url("//example.com/icon.svg")}"#,
            html: nil,
            links: [],
            group: nil
        )
        let first = ArticleReferenceItem(
            id: "first",
            label: "2",
            text: "First source",
            html: nil,
            links: [],
            group: nil
        )
        let second = ArticleReferenceItem(
            id: "second",
            label: "3",
            text: "Second source",
            html: nil,
            links: [],
            group: nil
        )

        let presentation = ReferenceListHelpers.Presentation.make(
            from: [
                ArticleReferenceSection(id: "empty", title: "Empty", items: [cssLeak]),
                ArticleReferenceSection(id: "sources", title: "Sources", items: [first, second])
            ]
        )

        #expect(presentation.sections.map(\.id) == ["sources"])
        #expect(presentation.sections.flatMap(\.items).map(\.id) == ["first", "second"])
        #expect(presentation.referenceIDs == ["first", "second"])
        #expect(presentation.totalCount == 2)
    }

    @Test func presentationFiltersExportsAgainstCurrentSelection() {
        let first = ArticleReferenceItem(
            id: "first",
            label: nil,
            text: "First source",
            html: nil,
            links: [],
            group: nil
        )
        let second = ArticleReferenceItem(
            id: "second",
            label: nil,
            text: "Second source",
            html: nil,
            links: [],
            group: nil
        )
        let presentation = ReferenceListHelpers.Presentation.make(
            from: [ArticleReferenceSection(id: "sources", title: "Sources", items: [first, second])]
        )

        let selected = presentation.selectedSections(for: ["second"])

        #expect(selected.count == 1)
        #expect(selected.first?.items.map(\.id) == ["second"])
        #expect(presentation.selectedSections(for: []).isEmpty)
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
            appState: AppState(persistenceMode: .ephemeral),
            item: item
        ) { url in
            openedURL = url
        }

        #expect(openedURL == URL(string: "https://example.com/source"))
    }
}
