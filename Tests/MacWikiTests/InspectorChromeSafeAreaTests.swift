import Foundation
import Testing

@Suite("Inspector chrome safe-area layout")
struct InspectorChromeSafeAreaTests {
    @Test("Notes chrome participates in native safe-area layout")
    func notesChromeUsesSafeAreaInsets() throws {
        let source = try source("Sources/MacWiki/Views/Components/HighlightListView.swift")

        #expect(source.contains(".safeAreaInset(edge: .top"))
        #expect(source.contains(".safeAreaInset(edge: .bottom"))
        #expect(!source.contains("topChromeReservation"))
        #expect(!source.contains("ZStack(alignment: .top)"))
    }

    @Test("References chrome participates in native safe-area layout")
    func referencesChromeUsesSafeAreaInsets() throws {
        let source = try source("Sources/MacWiki/Views/Inspector/ReferenceListView.swift")

        #expect(source.contains(".safeAreaInset(edge: .top"))
        #expect(source.contains(".safeAreaInset(edge: .bottom"))
        #expect(!source.contains("topChromeReservation"))
        #expect(!source.contains("bottomChromeReservation"))
        #expect(!source.contains(".overlay(alignment: .bottom)"))
        #expect(!source.contains("ZStack(alignment: .top)"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
