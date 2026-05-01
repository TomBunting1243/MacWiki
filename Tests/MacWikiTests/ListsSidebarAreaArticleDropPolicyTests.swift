import Foundation
import Testing

@testable import MacWiki

struct ListsSidebarAreaArticleDropPolicyTests {
    @Test func collapsedAreaArticleHoverSchedulesExpansionAndRejectsDirectDrop() {
        #expect(
            ListsSidebarAreaArticleDropPolicy.behavior(
                for: .articleHover,
                isExpanded: false
            ) == .expandAfterDelay(.milliseconds(300))
        )
        #expect(
            ListsSidebarAreaArticleDropPolicy.behavior(
                for: .directArticleDrop,
                isExpanded: false
            ) == .reject
        )
    }

    @Test func expandedAreaHoverDoesNothingAndCollectionDropsStayAccepted() {
        #expect(
            ListsSidebarAreaArticleDropPolicy.behavior(
                for: .articleHover,
                isExpanded: true
            ) == .noAction
        )
        #expect(
            ListsSidebarAreaArticleDropPolicy.behavior(
                for: .collectionDrop,
                isExpanded: false
            ) == .accept
        )
    }
}
