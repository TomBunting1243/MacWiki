import Testing

@testable import MacWiki

struct ReaderDocumentRevisionTests {
    @Test func middleOnlyChangesProduceDifferentFullDocumentRevisions() {
        let prefix = String(repeating: "p", count: 512)
        let suffix = String(repeating: "s", count: 512)
        let first = prefix + "A" + suffix
        let second = prefix + "B" + suffix

        #expect(first.utf8.count == second.utf8.count)
        #expect(first.utf8.prefix(512).elementsEqual(second.utf8.prefix(512)))
        #expect(first.utf8.suffix(512).elementsEqual(second.utf8.suffix(512)))
        #expect(ReaderDocumentRevision.digest(for: first) != ReaderDocumentRevision.digest(for: second))
    }
}
