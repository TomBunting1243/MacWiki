import Foundation
import Testing

@testable import MacWiki

struct ReaderDocumentVisibilityTests {
    @Test func onlyWikimediaPCSContainersOverrideCollapsedVisibility() throws {
        let stylesheet = try source("Sources/MacWiki/Resources/Reader.css")

        #expect(stylesheet.contains(".pcs-section-block:is([hidden], .pcs-hidden)"))
        #expect(stylesheet.contains(".pcs-collapse-block:is([hidden], .pcs-hidden)"))
        #expect(stylesheet.contains(".pcs-section-content:is([hidden], .pcs-hidden)"))
        #expect(!stylesheet.contains(".pcs-collapse-block, section"))
        #expect(!stylesheet.contains("[hidden], .pcs-hidden, .collapsed"))
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
