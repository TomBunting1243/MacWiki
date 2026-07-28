import Foundation
import SwiftData
import Testing

@testable import MacWiki

struct DirectoryDiscoverySurfaceRegressionTests {
    @Test func directoryLetsContentUseTheNativeTopSafeArea() throws {
        let source = try repositorySource("Sources/MacWiki/Views/Columns/DirectoryColumnView.swift")

        #expect(source.contains(".frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)"))
        #expect(!source.contains("SidebarPaneBackground()"))
        #expect(!source.contains(".ignoresSafeArea"))
        #expect(!source.contains("proxy.frame(in: .global)"))
        #expect(!source.contains("Task.sleep"))
        #expect(!source.contains("updateTrafficLightAvoidance"))
        #expect(!source.contains("measuredTopInset"))
        #expect(!source.contains("hasMeasuredTrafficLightAvoidance"))
    }

    @MainActor
    @Test func discoverRefreshesItsPreparedLookupAtTheModelSaveBoundary() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ReadingList.self,
            SavedArticle.self,
            configurations: configuration
        )
        let modelContext = ModelContext(container)
        let list = ReadingList(name: "Saved")
        modelContext.insert(list)
        try modelContext.save()

        let lookupModel = DiscoverArticleLookupModel()
        lookupModel.start(modelContext: modelContext)
        #expect(!lookupModel.index.isSaved(title: "Native SwiftUI"))

        let savedArticle = SavedArticle(title: "Native SwiftUI", list: list)
        list.articles.append(savedArticle)
        list.updatedAt = Date()
        modelContext.insert(savedArticle)
        try modelContext.save()

        #expect(lookupModel.index.isSaved(title: "Native SwiftUI"))

        list.articles.removeAll { $0.id == savedArticle.id }
        modelContext.delete(savedArticle)
        list.updatedAt = Date()
        try modelContext.save()

        #expect(!lookupModel.index.isSaved(title: "Native SwiftUI"))
        lookupModel.stop()
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
