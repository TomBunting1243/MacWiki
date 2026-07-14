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
