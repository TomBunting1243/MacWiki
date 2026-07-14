import Foundation
import Observation
import SwiftData

/// Keeps Discover's saved-article lookup in sync at the persistence boundary.
/// Search and animation updates can then reuse the prepared index without
/// traversing every reading-list relationship during view evaluation.
@MainActor
@Observable
final class DiscoverArticleLookupModel: NSObject {
    private(set) var index = ArticleLookupIndex.empty

    private var modelContext: ModelContext?

    override init() {
        super.init()
    }

    func start(modelContext: ModelContext) {
        guard self.modelContext != modelContext else { return }

        stop()
        self.modelContext = modelContext
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(modelContextDidSave(_:)),
            name: ModelContext.didSave,
            object: modelContext
        )
        refresh()
    }

    func stop() {
        guard let modelContext else { return }
        NotificationCenter.default.removeObserver(
            self,
            name: ModelContext.didSave,
            object: modelContext
        )
        self.modelContext = nil
    }

    @objc private func modelContextDidSave(_ notification: Notification) {
        refresh()
    }

    private func refresh() {
        guard let modelContext else { return }
        guard let readingLists = try? modelContext.fetch(FetchDescriptor<ReadingList>()) else {
            return
        }
        index = ArticleLookupIndex(readingLists: readingLists)
    }
}
