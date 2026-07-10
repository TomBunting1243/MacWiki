import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct PersistenceIssueCenterTests {
    @Test func reportedFailurePreservesOperationAndCanBeDismissed() {
        let center = PersistenceIssueCenter()
        let error = NSError(
            domain: "PersistenceIssueCenterTests",
            code: 7,
            userInfo: [NSLocalizedDescriptionKey: "Synthetic save failure"]
        )

        center.report(operation: "rename a list", error: error)

        #expect(center.activeIssue?.operation == "rename a list")
        #expect(center.activeIssue?.detail == "Synthetic save failure")

        center.dismiss()
        #expect(center.activeIssue == nil)
    }

    @Test func reportingSavePersistsValidChanges() throws {
        let modelContext = try makeInMemoryModelContext()
        modelContext.insert(ReadingList(name: "Research"))

        #expect(modelContext.saveReportingFailure(operation: "create a list"))

        let savedLists = try modelContext.fetch(FetchDescriptor<ReadingList>())
        #expect(savedLists.map(\.name) == ["Research"])
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            Label.self,
            ReadingList.self,
            SavedArticle.self,
            Highlight.self,
            configurations: configuration
        )
        return ModelContext(container)
    }
}
