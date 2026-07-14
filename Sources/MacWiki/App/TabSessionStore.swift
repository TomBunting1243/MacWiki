import Foundation
import Observation
import SwiftUI
import os

private let tabSessionLogger = Logger(subsystem: "com.macwiki", category: "tab-session")

enum TabContent: Hashable, Codable {
    case placeholder
    case history(items: [HistoryItem], currentIndex: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case items
        case currentIndex
    }

    private enum Kind: String, Codable {
        case placeholder
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)

        switch kind {
        case .placeholder:
            self = .placeholder
        case .history:
            let items = try container.decode([HistoryItem].self, forKey: .items)
            let currentIndex = try container.decode(Int.self, forKey: .currentIndex)
            self = .history(
                items: items,
                currentIndex: Self.clampedIndex(currentIndex, count: items.count)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .placeholder:
            try container.encode(Kind.placeholder, forKey: .kind)
        case .history(let items, let currentIndex):
            try container.encode(Kind.history, forKey: .kind)
            try container.encode(items, forKey: .items)
            try container.encode(Self.clampedIndex(currentIndex, count: items.count), forKey: .currentIndex)
        }
    }

    private static func clampedIndex(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

struct TabSessionSnapshot: Codable {
    static let currentVersion = 2

    let version: Int
    let openTabs: [ArticleTab]
    let activeTabId: UUID?
    let recentlyClosedTabs: [ArticleTab]

    init(
        version: Int = TabSessionSnapshot.currentVersion,
        openTabs: [ArticleTab],
        activeTabId: UUID?,
        recentlyClosedTabs: [ArticleTab]
    ) {
        self.version = version
        self.openTabs = openTabs
        self.activeTabId = activeTabId
        self.recentlyClosedTabs = recentlyClosedTabs
    }
}

struct TabSessionMutationResult: Equatable {
    enum Event: Equatable {
        case articleOpened(article: Article, tabID: UUID)
    }

    static let none = TabSessionMutationResult(events: [])

    let events: [Event]

    var openedArticle: Article? {
        for event in events {
            if case .articleOpened(let article, _) = event {
                return article
            }
        }
        return nil
    }
}

@Observable @MainActor
final class TabSessionStore {
    private struct LegacySavedState: Codable {
        let openTabs: [ArticleTab]
        let activeTabId: UUID?
    }

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    @ObservationIgnored
    private let persistenceQueue = DispatchQueue(label: "MacWiki.TabSession.Persistence", qos: .utility)
    @ObservationIgnored
    private let persistenceQueueKey = DispatchSpecificKey<Void>()
    @ObservationIgnored
    let persistenceMode: AppStatePersistenceMode
#if DEBUG
    @ObservationIgnored
    private(set) var saveRequestGeneration = 0
#endif

    var openTabs: [ArticleTab] = []
    var activeTabId: UUID?
    var recentlyClosedTabs: [ArticleTab] = []

    init(persistenceMode: AppStatePersistenceMode = .shared) {
        self.persistenceMode = persistenceMode
        persistenceQueue.setSpecific(key: persistenceQueueKey, value: ())
        if persistenceMode.isEnabled {
            load()
        }
    }

    var currentTab: ArticleTab? {
        guard let activeTabId else { return nil }
        return openTabs.first(where: { $0.id == activeTabId })
    }

    var currentArticle: Article? {
        currentTab?.currentArticle
    }

    @discardableResult
    func selectTab(id: UUID) -> Bool {
        guard id != activeTabId,
              openTabs.contains(where: { $0.id == id }) else {
            return false
        }
        activeTabId = id
        requestSave()
        return true
    }

    func openArticle(
        _ article: Article,
        inNewTab: Bool = false,
        activateNewTab: Bool = true
    ) -> TabSessionMutationResult {
        if inNewTab {
            let tab = ArticleTab(article: article)
            openTabs.append(tab)
            if activateNewTab || activeTabId == nil {
                activeTabId = tab.id
            }
            requestSave()
            return TabSessionMutationResult(events: [.articleOpened(article: article, tabID: tab.id)])
        }

        if let activeId = activeTabId,
           let index = openTabs.firstIndex(where: { $0.id == activeId }) {
            var tab = openTabs[index]

            if tab.isPlaceholder {
                tab.replacePlaceholder(with: article)
                openTabs[index] = tab
                requestSave()
                return TabSessionMutationResult(events: [.articleOpened(article: article, tabID: tab.id)])
            }

            if ReadStateSync.normalizedTitle(tab.article.title) == ReadStateSync.normalizedTitle(article.title) {
                return .none
            }

            tab.truncateForwardHistory()
            tab.appendToHistory(article)
            openTabs[index] = tab
            requestSave()
            return TabSessionMutationResult(events: [.articleOpened(article: article, tabID: tab.id)])
        }

        let tab = ArticleTab(article: article)
        openTabs.append(tab)
        activeTabId = tab.id
        requestSave()
        return TabSessionMutationResult(events: [.articleOpened(article: article, tabID: tab.id)])
    }

    func openArticleInNewTab(_ article: Article, activate: Bool = true) -> TabSessionMutationResult {
        openArticle(article, inNewTab: true, activateNewTab: activate)
    }

    func createNewTab() {
        let tab = ArticleTab()
        openTabs.append(tab)
        activeTabId = tab.id
        requestSave()
    }

    func showDiscoverPage() {
        if let existingDiscoverTab = openTabs.first(where: \.isPlaceholder) {
            activeTabId = existingDiscoverTab.id
            requestSave()
            return
        }
        createNewTab()
    }

    func goBack() {
        guard let index = openTabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        var tab = openTabs[index]
        guard tab.canGoBack else { return }
        tab.moveBack()
        openTabs[index] = tab
        requestSave()
    }

    func goForward() {
        guard let index = openTabs.firstIndex(where: { $0.id == activeTabId }) else { return }
        var tab = openTabs[index]
        guard tab.canGoForward else { return }
        tab.moveForward()
        openTabs[index] = tab
        requestSave()
    }

    func nextTab() {
        guard !openTabs.isEmpty,
              let currentActiveTabID = self.activeTabId,
              let currentIndex = openTabs.firstIndex(where: { $0.id == currentActiveTabID }) else { return }
        activeTabId = openTabs[(currentIndex + 1) % openTabs.count].id
        requestSave()
    }

    func previousTab() {
        guard !openTabs.isEmpty,
              let currentActiveTabID = self.activeTabId,
              let currentIndex = openTabs.firstIndex(where: { $0.id == currentActiveTabID }) else { return }
        activeTabId = openTabs[(currentIndex - 1 + openTabs.count) % openTabs.count].id
        requestSave()
    }

    func closeActiveTab() {
        guard let activeTabId else { return }
        closeTab(activeTabId)
    }

    func closeTab(_ id: UUID) {
        guard let closedIndex = openTabs.firstIndex(where: { $0.id == id }) else { return }
        let closedTab = openTabs.remove(at: closedIndex)
        recentlyClosedTabs.append(closedTab)
        trimRecentlyClosedTabsIfNeeded()

        if activeTabId == id {
            if openTabs.isEmpty {
                activeTabId = nil
            } else {
                activeTabId = openTabs[min(closedIndex, openTabs.count - 1)].id
            }
        }

        requestSave()
    }

    func reopenLastClosedTab() {
        guard let tab = recentlyClosedTabs.popLast() else { return }
        openTabs.append(tab)
        activeTabId = tab.id
        requestSave()
    }

    func duplicateTab(id: UUID) {
        guard let tab = openTabs.first(where: { $0.id == id }) else { return }
        let duplicate = tab.duplicated()
        if let sourceIndex = openTabs.firstIndex(where: { $0.id == id }) {
            openTabs.insert(duplicate, at: sourceIndex + 1)
        } else {
            openTabs.append(duplicate)
        }
        activeTabId = duplicate.id
        requestSave()
    }

    func closeOtherTabs(keeping id: UUID) {
        let toClose = openTabs.filter { $0.id != id }
        guard !toClose.isEmpty else { return }
        recentlyClosedTabs.append(contentsOf: toClose)
        trimRecentlyClosedTabsIfNeeded()
        openTabs.removeAll { $0.id != id }
        activeTabId = id
        requestSave()
    }

    func moveTab(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              openTabs.indices.contains(sourceIndex),
              destinationIndex >= 0,
              destinationIndex <= openTabs.count else { return }

        let tab = openTabs.remove(at: sourceIndex)
        openTabs.insert(tab, at: max(0, min(destinationIndex, openTabs.count)))
        requestSave()
    }

    /// Applies an identity-based reorder emitted by SwiftUI's native reorder
    /// container. Identity keeps the mutation stable if the visible order
    /// changes between drag recognition and drop delivery.
    @discardableResult
    func reorderTabs(_ sourceIDs: [UUID], before destinationID: UUID?) -> Bool {
        let sourceSet = Set(sourceIDs)
        guard !sourceSet.isEmpty else { return false }

        let movedTabs = openTabs.filter { sourceSet.contains($0.id) }
        guard movedTabs.count == sourceSet.count else { return false }

        var reordered = openTabs.filter { !sourceSet.contains($0.id) }
        let insertionIndex: Int
        if let destinationID,
           let destinationIndex = reordered.firstIndex(where: { $0.id == destinationID }) {
            insertionIndex = destinationIndex
        } else {
            insertionIndex = reordered.endIndex
        }
        reordered.insert(contentsOf: movedTabs, at: insertionIndex)

        guard reordered.map(\.id) != openTabs.map(\.id) else { return false }
        openTabs = reordered
        requestSave()
        return true
    }

    @discardableResult
    func updateArticleMetadata(ids: Set<String>, description: String?, extract: String?, wordCount: Int?) -> Bool {
        guard !ids.isEmpty else { return false }

        var tabs = openTabs
        var didChange = false

        for tabIndex in tabs.indices {
            for historyIndex in tabs[tabIndex].history.indices {
                let article = tabs[tabIndex].history[historyIndex].article
                guard ids.contains(article.id) else { continue }

                tabs[tabIndex].updateHistoryItem(at: historyIndex) { item in
                    if let description, item.article.description != description {
                        item.article.description = description
                        didChange = true
                    }
                    if let extract, item.article.extract != extract {
                        item.article.extract = extract
                        didChange = true
                    }
                    if let wordCount, item.article.wordCount != wordCount {
                        item.article.wordCount = wordCount
                        didChange = true
                    }
                }
            }
        }

        guard didChange else { return false }
        openTabs = tabs
        requestSave()
        return true
    }

    @discardableResult
    func updateReadState(forTitle title: String, isRead: Bool) -> Bool {
        let normalized = ReadStateSync.normalizedTitle(title)
        var tabs = openTabs
        var didChange = false

        for tabIndex in tabs.indices {
            for historyIndex in tabs[tabIndex].history.indices {
                let candidate = ReadStateSync.normalizedTitle(tabs[tabIndex].history[historyIndex].article.title)
                guard candidate == normalized else { continue }

                tabs[tabIndex].updateHistoryItem(at: historyIndex) { item in
                    guard item.article.isRead != isRead else { return }
                    item.article.isRead = isRead
                    didChange = true
                }
            }
        }

        guard didChange else { return false }
        openTabs = tabs
        requestSave()
        return true
    }

    func requestSave() {
#if DEBUG
        saveRequestGeneration += 1
#endif
        guard persistenceMode.isEnabled else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            self?.performSave()
        }
    }

    func flushSaveNow() {
        guard persistenceMode.isEnabled else { return }
        saveTask?.cancel()
        performSave(sync: true)
    }

#if DEBUG
    var hasPendingSaveForTesting: Bool {
        saveTask != nil
    }

    func cancelPendingSaveForTesting() {
        saveTask?.cancel()
        saveTask = nil
    }
#endif

    func resetForFactoryDefaults() {
        saveTask?.cancel()
        saveTask = nil
        openTabs.removeAll()
        activeTabId = nil
        recentlyClosedTabs.removeAll()

        if persistenceMode.isEnabled, let url = persistenceURL {
            try? FileManager.default.removeItem(at: url)
            let backup = url.deletingPathExtension().appendingPathExtension("corrupted.json")
            try? FileManager.default.removeItem(at: backup)
        }
    }

    private func trimRecentlyClosedTabsIfNeeded() {
        if recentlyClosedTabs.count > 20 {
            recentlyClosedTabs.removeFirst(recentlyClosedTabs.count - 20)
        }
    }

    @MainActor
    private func performSave() {
        performSave(sync: false)
    }

    @MainActor
    private func performSave(sync: Bool) {
        guard persistenceMode.isEnabled else { return }
        let snapshot = TabSessionSnapshot(
            openTabs: openTabs,
            activeTabId: activeTabId,
            recentlyClosedTabs: recentlyClosedTabs
        )

        let targetURL = persistenceURL
        if sync {
            if DispatchQueue.getSpecific(key: persistenceQueueKey) != nil {
                Self.writeSnapshot(snapshot, to: targetURL)
            } else {
                persistenceQueue.sync {
                    Self.writeSnapshot(snapshot, to: targetURL)
                }
            }
        } else {
            persistenceQueue.async {
                Self.writeSnapshot(snapshot, to: targetURL)
            }
        }
    }

    private func load() {
        guard persistenceMode.isEnabled else { return }
        if let snapshotURL = persistenceURL {
            let loadResult = readSnapshot(from: snapshotURL)
            switch loadResult {
            case .success(let snapshot):
                apply(snapshot: snapshot)
                return
            case .failure(let error, let byteCount):
                tabSessionLogger.error("Failed to decode tab snapshot: \(error.localizedDescription, privacy: .public)")
                let backup = snapshotURL.deletingPathExtension().appendingPathExtension("corrupted.json")
                try? FileManager.default.removeItem(at: backup)
                try? FileManager.default.moveItem(at: snapshotURL, to: backup)
                PerformanceMetricsStore.shared.record(
                    kind: .sessionRestore,
                    durationMs: 0,
                    detail: "tab-session-failed bytes=\(byteCount ?? 0)"
                )
            case .missing:
                break
            }
        }

        guard let legacyURL = legacyStateURL else { return }
        switch readLegacyState(from: legacyURL) {
        case .success(let legacy):
            openTabs = legacy.openTabs
            activeTabId = legacy.activeTabId
            normalizeActiveTabIfNeeded()
            flushSaveNow()
        case .failure(let error, _):
            tabSessionLogger.error("Failed to decode legacy tab state: \(error.localizedDescription, privacy: .public)")
        case .missing:
            break
        }
    }

    private func apply(snapshot: TabSessionSnapshot) {
        openTabs = snapshot.openTabs
        activeTabId = snapshot.activeTabId
        recentlyClosedTabs = snapshot.recentlyClosedTabs
        normalizeActiveTabIfNeeded()
    }

    private func normalizeActiveTabIfNeeded() {
        if let activeTabId,
           !openTabs.contains(where: { $0.id == activeTabId }) {
            self.activeTabId = openTabs.first?.id
        }
    }

    private enum SnapshotLoadResult {
        case missing
        case success(TabSessionSnapshot)
        case failure(Error, byteCount: Int?)
    }

    private enum LegacyLoadResult {
        case missing
        case success(LegacySavedState)
        case failure(Error, byteCount: Int?)
    }

    private func readSnapshot(from url: URL) -> SnapshotLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        do {
            let data = try Data(contentsOf: url)
            do {
                return .success(try JSONDecoder().decode(TabSessionSnapshot.self, from: data))
            } catch {
                return .failure(error, byteCount: data.count)
            }
        } catch {
            return .failure(error, byteCount: nil)
        }
    }

    private func readLegacyState(from url: URL) -> LegacyLoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }

        do {
            let data = try Data(contentsOf: url)
            do {
                return .success(try JSONDecoder().decode(LegacySavedState.self, from: data))
            } catch {
                return .failure(error, byteCount: data.count)
            }
        } catch {
            return .failure(error, byteCount: nil)
        }
    }

    nonisolated private static func writeSnapshot(_ snapshot: TabSessionSnapshot, to url: URL?) {
        guard let url else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            tabSessionLogger.error("Failed to save tab snapshot: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var persistenceURL: URL? {
        guard persistenceMode.isEnabled else { return nil }
        return Self.applicationSupportDirectory?.appendingPathComponent("tab-session.json")
    }

    private var legacyStateURL: URL? {
        guard persistenceMode.isEnabled else { return nil }
        return Self.applicationSupportDirectory?.appendingPathComponent("state.json")
    }

    private static var applicationSupportDirectory: URL? {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let appDir = supportDir.appendingPathComponent("MacWiki")
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }
}
