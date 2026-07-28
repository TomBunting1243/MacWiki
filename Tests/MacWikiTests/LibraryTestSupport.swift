import Foundation
import SwiftData

@testable import MacWiki

@MainActor
func makeInMemoryLibraryContext() throws -> ModelContext {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
        for: ArticleNote.self,
        ArticleState.self,
        Area.self,
        Highlight.self,
        Label.self,
        ReadingList.self,
        SavedArticle.self,
        Tag.self,
        configurations: configuration
    )
    return ModelContext(container)
}

@MainActor
func makeReadOnlyLibraryContext(
    storeName: String,
    seed: (ModelContext) throws -> Void = { _ in }
) throws -> (context: ModelContext, directoryURL: URL) {
    let directoryURL = FileManager.default.temporaryDirectory
        .appending(path: "MacWiki-\(storeName)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
    )
    let storeURL = directoryURL.appending(path: "\(storeName).store")
    let schema = Schema([
        ArticleNote.self,
        ArticleState.self,
        Area.self,
        Highlight.self,
        Label.self,
        ReadingList.self,
        SavedArticle.self,
        Tag.self
    ])

    do {
        let writableConfiguration = ModelConfiguration(schema: schema, url: storeURL)
        let writableContainer = try ModelContainer(
            for: schema,
            configurations: writableConfiguration
        )
        let writableContext = ModelContext(writableContainer)
        try seed(writableContext)
        try writableContext.save()
    }

    let readOnlyConfiguration = ModelConfiguration(
        schema: schema,
        url: storeURL,
        allowsSave: false
    )
    let readOnlyContainer = try ModelContainer(
        for: schema,
        configurations: readOnlyConfiguration
    )
    return (ModelContext(readOnlyContainer), directoryURL)
}
