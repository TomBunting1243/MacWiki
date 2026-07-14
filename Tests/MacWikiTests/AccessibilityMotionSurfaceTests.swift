import Foundation
import Testing

@testable import MacWiki

@MainActor
struct AccessibilityMotionSurfaceTests {
    @Test func scopedInteractiveMotionHonorsAccessibilityPersonalization() throws {
        let highlightRow = try source("Sources/MacWiki/Views/Components/HighlightRowView.swift")
        let sidebarSearch = try source("Sources/MacWiki/Views/Sidebar/SidebarSearchView.swift")
        let searchResults = try source("Sources/MacWiki/Views/Sidebar/Search/SidebarSearchResultsView.swift")
        let timeMachine = try source("Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineControlsView.swift")

        for surface in [highlightRow, sidebarSearch, searchResults, timeMachine] {
            #expect(surface.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceMotion)"))
        }

        #expect(highlightRow.components(separatedBy: "withAnimation(reduceMotion ? nil :").count - 1 == 8)
        #expect(!highlightRow.contains("withAnimation(."))
        #expect(sidebarSearch.contains("withAnimation(reduceMotion ? nil : ColumnMotion.sidebarVisibility)"))
        #expect(searchResults.contains("withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15))"))
        #expect(searchResults.contains("proxy.scrollTo(newValue, anchor: .center)"))
        #expect(timeMachine.components(separatedBy: "reduceMotion\n                                ? .opacity").count - 1 == 2)
        #expect(timeMachine.contains(".animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isScanning)"))
    }

    @Test func timeMachineIconControlsExposeSemanticAccessibilityMetadata() throws {
        let source = try source("Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineControlsView.swift")

        #expect(source.contains(".accessibilityLabel(\"Refresh Discover\")"))
        #expect(source.contains(".accessibilityValue(discoverFeedStore.isLoading ? \"Refreshing\" : \"Ready\")"))
        #expect(source.contains(".help(\"Refresh Discover\")"))

        #expect(source.contains(".accessibilityLabel(\"Jump to Date\")"))
        #expect(source.contains(".accessibilityValue(Text(screenModel.discoverTimeMachineDateLabel))"))
        #expect(source.contains(".help(\"Jump to a relative date\")"))

        #expect(source.components(separatedBy: "accessibilityLabel: \"Previous Day\"").count - 1 == 2)
        #expect(source.components(separatedBy: "accessibilityLabel: \"Next Day\"").count - 1 == 2)
        #expect(source.contains(".accessibilityLabel(Text(accessibilityLabel))"))
        #expect(source.contains(".help(Text(help))"))
    }

    private func source(_ relativePath: String) throws -> String {
        try String(contentsOf: repositoryRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
