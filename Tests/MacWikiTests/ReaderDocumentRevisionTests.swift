import Foundation
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

    @Test func readerStoresTheRevisionAtTheArticleLoadBoundary() throws {
        let reader = try source("Sources/MacWiki/Views/Reader/ReaderView.swift")
        let webView = try source("Sources/MacWiki/Views/Components/WebView.swift")

        #expect(reader.contains("htmlContentRevision = ReaderDocumentRevision.digest(for: preloadedHTML)"))
        #expect(reader.contains("htmlContentRevision = ReaderDocumentRevision.digest(for: content.html)"))
        #expect(reader.contains("contentRevision: htmlRevision"))
        #expect(webView.contains("let htmlSignature = contentRevision"))
        #expect(!webView.contains("utf8.prefix(512)"))
        #expect(!webView.contains("utf8.suffix(512)"))
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
