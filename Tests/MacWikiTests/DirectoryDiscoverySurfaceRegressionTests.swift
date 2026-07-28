import Foundation
import SwiftData
import Testing

@testable import MacWiki

struct DirectoryDiscoverySurfaceRegressionTests {
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
}
