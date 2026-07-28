import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct LibraryResetServiceTests {
    @Test func resetDeletesEveryPersistedLibraryType() throws {
        let context = try makeInMemoryLibraryContext()
        let articleURL = try #require(URL(string: "https://en.wikipedia.org/wiki/Ada_Lovelace"))
        context.insert(ArticleNote(content: "Note", articleTitle: "Ada Lovelace"))
        context.insert(
            ArticleState(
                articleTitle: "Ada Lovelace",
                articleURL: articleURL
            )
        )
        context.insert(Area(name: "People"))
        context.insert(
            Highlight(
                text: "Analytical Engine",
                articleTitle: "Ada Lovelace",
                startOffset: 0,
                length: 17
            )
        )
        context.insert(Label(name: "Computing"))
        context.insert(ReadingList(name: "Research"))
        context.insert(SavedArticle(title: "Ada Lovelace"))
        context.insert(MacWiki.Tag(name: "history"))
        try context.save()

        try LibraryResetService.deleteAll(in: context)

        #expect(try context.fetchCount(FetchDescriptor<ArticleNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ArticleState>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Area>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Highlight>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Label>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReadingList>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SavedArticle>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<MacWiki.Tag>()) == 0)
        #expect(!context.hasChanges)
    }

    @Test func failedResetRollsBackAndPropagatesTheSaveError() throws {
        let fixture = try makeReadOnlyLibraryContext(
            storeName: "LibraryResetServiceTests"
        ) { context in
            context.insert(ReadingList(name: "Keep Me"))
        }
        defer {
            try? FileManager.default.removeItem(at: fixture.directoryURL)
        }

        #expect(throws: (any Error).self) {
            try LibraryResetService.deleteAll(in: fixture.context)
        }

        let remaining = try fixture.context.fetch(FetchDescriptor<ReadingList>())
        #expect(remaining.map(\.name) == ["Keep Me"])
        #expect(!fixture.context.hasChanges)
    }
}
