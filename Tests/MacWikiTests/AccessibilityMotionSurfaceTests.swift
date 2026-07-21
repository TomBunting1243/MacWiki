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
        let sidebarTimeMachine = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverTimeMachineView.swift"
        )
        let listsSidebar = try source("Sources/MacWiki/Views/Sidebar/ListsSidebar.swift")

        for surface in [highlightRow, sidebarSearch, searchResults, timeMachine, sidebarTimeMachine] {
            #expect(surface.contains("@Environment(\\.macWikiAccessibilityPersonalization.reduceMotion)"))
        }

        #expect(highlightRow.components(separatedBy: "withAnimation(reduceMotion ? nil :").count - 1 == 8)
        #expect(!highlightRow.contains("withAnimation(."))
        #expect(sidebarSearch.contains("withAnimation(reduceMotion ? nil : ColumnMotion.sidebarVisibility)"))
        #expect(searchResults.contains("withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15))"))
        #expect(searchResults.contains("proxy.scrollTo(newValue, anchor: .center)"))
        #expect(timeMachine.contains(".transition(reduceMotion ? .opacity"))
        #expect(timeMachine.contains(".animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isScanning)"))
        #expect(sidebarTimeMachine.components(separatedBy: "withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16))").count - 1 == 2)
        #expect(sidebarTimeMachine.contains("ViewThatFits(in: .horizontal)"))
        #expect(sidebarTimeMachine.contains("wideControls"))
        #expect(sidebarTimeMachine.contains("compactControls"))
        #expect(!sidebarTimeMachine.contains("GroupBox"))
        #expect(!sidebarTimeMachine.contains("ControlGroup"))
        #expect(!sidebarTimeMachine.contains("discoverSurfaceChrome"))
        #expect(!sidebarTimeMachine.contains("strokeBorder"))
        #expect(listsSidebar.contains("withAnimation(reduceMotion ? nil : .default)"))
    }

    @Test func timeMachineIconControlsExposeSemanticAccessibilityMetadata() throws {
        let timeMachineSource = try source("Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineControlsView.swift")

        #expect(timeMachineSource.contains(".accessibilityLabel(\"Refresh Discover\")"))
        #expect(timeMachineSource.contains(".accessibilityValue(discoverFeedStore.isLoading ? \"Refreshing\" : \"Ready\")"))
        #expect(timeMachineSource.contains(".help(discoverFeedStore.isLoading ? \"Refreshing Discover…\" : \"Refresh Discover\")"))

        #expect(timeMachineSource.contains("Menu(\"Jump\", systemImage: \"calendar.badge.clock\")"))
        #expect(timeMachineSource.contains(".help(\"Jump to another edition\")"))

        #expect(timeMachineSource.contains("Button(\"Previous Day\", systemImage: \"chevron.left\")"))
        #expect(timeMachineSource.contains("Button(\"Next Day\", systemImage: \"chevron.right\")"))
        #expect(timeMachineSource.contains("DatePicker("))
        #expect(timeMachineSource.contains(".datePickerStyle(.field)"))
        #expect(timeMachineSource.contains(".frame(width: 126)"))
        #expect(!timeMachineSource.contains("ControlGroup"))
        #expect(timeMachineSource.contains(".accessibilityLabel(\"Edition Date\")"))

        let sidebarSource = try source(
            "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverTimeMachineView.swift"
        )
        #expect(sidebarSource.contains(".frame(width: 112)"))
        #expect(sidebarSource.contains(".buttonStyle(.borderless)"))
        #expect(sidebarSource.contains(".menuIndicator(.hidden)"))
        #expect(sidebarSource.contains(".disabled(isBusy)"))
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
