import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct PersistenceIssueCenterTests {
    @Test func persistenceAlertUsesTheModernBackDeployablePresentationAPI() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/MacWiki/Utilities/PersistenceIssueCenter.swift"
            ),
            encoding: .utf8
        )

        #expect(source.contains("isPresented: isPresented"))
        #expect(source.contains("presenting: issueCenter.activeIssue"))
        #expect(source.contains("Button(\"OK\")"))
        #expect(!source.contains("\n            Alert("))
        #expect(!source.contains(".alert(item:"))
    }

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

    private var repositoryRoot: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
