import Foundation
import Testing

@testable import MacWiki

struct DiscoverInteractionRegressionTests {
    @Test func trendDetailsAreRealSiblingButtonsWithoutGestureSuppression() throws {
        let feature = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverFeatureComponents.swift"
        )
        let news = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverNewsComponents.swift"
        )

        #expect(news.contains("Button(action: onTap)"))
        #expect(news.contains("if let trendPulse, let onTrendTapped"))
        #expect(!news.contains(".highPriorityGesture("))
        #expect(!news.contains("suppressPrimaryTapFromTrend"))
        #expect(!feature.contains("suppressPrimaryTapFromTrend"))
        #expect(!feature.contains("Task.sleep(nanoseconds:"))
        #expect(!news.contains("Task.sleep(nanoseconds:"))
    }

    @Test func unlinkedEditorialRowsAreStaticAndSearchResultsExposeSavedState() throws {
        let resultRows = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverResultRows.swift"
        )
        let temporalRows = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverTemporalSupport.swift"
        )
        let mediaRows = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverMediaSupport.swift"
        )

        #expect(resultRows.contains("if let article = holiday.article"))
        #expect(resultRows.contains(".accessibilityValue(isSaved ? \"Saved\" : \"Not Saved\")"))
        #expect(temporalRows.contains("if let article = event.article"))
        #expect(temporalRows.contains("if let article = fact.article"))
        #expect(resultRows.contains("isHovered && holiday.article != nil"))
        #expect(temporalRows.contains("isHovered && event.article != nil"))
        #expect(temporalRows.contains("isHovered && fact.article != nil"))
        #expect(!temporalRows.contains(".disabled(event.article == nil)"))
        #expect(!mediaRows.contains(".disabled(image.filePageURL == nil)"))
    }

    private func repositorySource(_ relativePath: String) throws -> String {
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
