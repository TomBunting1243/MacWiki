import Foundation
import SwiftData
import Testing

@testable import MacWiki

@MainActor
struct ReaderStateTests {
    @Test func promptPolicyRequiresEligibilityDelayAndMeaningfulScroll() {
        var policy = ReaderPromptPolicy()
        policy.resetForSession(startProgress: 0.20, now: 100)

        // Before eligibility window, scroll updates should not count.
        policy.noteScrollChange(oldValue: 0, newValue: 100, now: 100.5)
        #expect(
            policy.shouldShowPrompt(
                forProgress: 0.95,
                isArticleUnread: true,
                isPromptAlreadyVisible: false
            ) == false
        )

        // After eligibility window, accumulate realistic scroll travel.
        policy.noteScrollChange(oldValue: 0, newValue: 90, now: 102)
        policy.noteScrollChange(oldValue: 90, newValue: 205, now: 102.1)
        policy.noteScrollChange(oldValue: 205, newValue: 320, now: 102.2)

        #expect(
            policy.shouldShowPrompt(
                forProgress: 0.95,
                isArticleUnread: true,
                isPromptAlreadyVisible: false
            ) == true
        )
    }

    @Test func progressCoordinatorSuppressesEarlyTopRegression() throws {
        let appState = AppState(persistenceMode: .ephemeral)
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Swift", title: "Swift")
        var coordinator = ReaderProgressCoordinator()

        coordinator.bootstrapFromPersisted(0.58, articleTitle: article.title, appState: appState, now: 100)
        let telemetryAccepted = coordinator.consumeTelemetry(
            0.02,
            for: article,
            in: modelContext,
            appState: appState,
            now: 101
        )

        #expect(telemetryAccepted == nil)
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 0.58))
        #expect(ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext) == nil)
    }

    @Test func progressCoordinatorPersistsMeaningfulDeltas() throws {
        let appState = AppState(persistenceMode: .ephemeral)
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Swift", title: "Swift")
        var coordinator = ReaderProgressCoordinator()

        coordinator.bootstrapFromPersisted(0.20, articleTitle: article.title, appState: appState, now: 10)

        _ = coordinator.consumeTelemetry(0.21, for: article, in: modelContext, appState: appState, now: 11)
        var state = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
        #expect(state == nil)

        _ = coordinator.consumeTelemetry(0.24, for: article, in: modelContext, appState: appState, now: 11.2)
        state = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
        #expect(state != nil)
        #expect(approximatelyEqual(state?.readingProgress, 0.24))
    }

    @Test func progressCoordinatorCanDeferLivePublicationUntilReveal() throws {
        let appState = AppState(persistenceMode: .ephemeral)
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Grace", title: "Grace Hopper")
        var coordinator = ReaderProgressCoordinator()

        coordinator.bootstrapFromPersisted(0.18, articleTitle: article.title, appState: appState, now: 10)

        let telemetryAccepted = coordinator.consumeTelemetry(
            0.41,
            for: article,
            in: modelContext,
            appState: appState,
            publishLiveProgress: false,
            now: 11
        )

        #expect(approximatelyEqual(telemetryAccepted, 0.41))
        #expect(approximatelyEqual(coordinator.latestReadingProgress, 0.41))
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 0.18))

        coordinator.publishLatestProgress(for: article, appState: appState)
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 0.41))
    }

    @Test func progressCoordinatorForcePersistSupportsTransitionFlush() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Ada", title: "Ada Lovelace")
        var coordinator = ReaderProgressCoordinator()

        coordinator.persist(progress: 0.61, for: article, in: modelContext, force: true, now: 50)

        let state = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
        #expect(state != nil)
        #expect(approximatelyEqual(state?.readingProgress, 0.61))
    }

    @Test func markAsCompletedSetsReadStateAndFullProgress() throws {
        let appState = AppState(persistenceMode: .ephemeral)
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Turing", title: "Alan Turing")
        var coordinator = ReaderProgressCoordinator()

        let completed = coordinator.markAsCompleted(
            for: article,
            in: modelContext,
            appState: appState,
            now: 500
        )

        #expect(completed)
        let state = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
        #expect(state != nil)
        #expect(state?.isRead == true)
        #expect(approximatelyEqual(state?.readingProgress, 1))
        #expect(approximatelyEqual(coordinator.latestReadingProgress, 1))
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 1))
    }

    @Test func applyReadStatePersistsBeforePublishingAppState() throws {
        let appState = AppState(persistenceMode: .ephemeral)
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "read-boundary", title: "Read Boundary", isRead: false)
        let list = ReadingList(name: "Inbox")
        let savedArticle = SavedArticle(title: article.title, list: list)
        savedArticle.isRead = false
        list.articles = [savedArticle]
        modelContext.insert(list)
        try modelContext.save()
        appState.openArticle(article)

        let succeeded = ReadStateSync.applyReadState(
            true,
            for: article,
            in: modelContext,
            appState: appState
        )

        #expect(succeeded)
        #expect(ReadStateSync.fetchArticleState(
            forURLString: article.url.absoluteString,
            in: modelContext
        )?.isRead == true)
        #expect(savedArticle.isRead)
        #expect(appState.currentArticle?.isRead == true)
    }

    @Test func progressNoOpDoesNotInsertArticleState() throws {
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "no-progress", title: "No Progress")

        let persisted = ReadStateSync.updateReadingProgress(
            0,
            for: article,
            in: modelContext
        )

        #expect(persisted == 0)
        #expect(ReadStateSync.fetchArticleState(
            forURLString: article.url.absoluteString,
            in: modelContext
        ) == nil)
        #expect(!modelContext.hasChanges)
    }

    @Test func failedReadStateSaveRollsBackAndDoesNotPublish() throws {
        let article = Article(id: "read-failure", title: "Read Failure", isRead: false)
        let fixture = try makeReadOnlyModelContext { context in
            context.insert(ArticleState(
                articleTitle: article.title,
                articleURL: article.url,
                isRead: false
            ))
        }
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openArticle(article)
        PersistenceIssueCenter.shared.dismiss()

        let succeeded = ReadStateSync.applyReadState(
            true,
            for: article,
            in: fixture.modelContext,
            appState: appState
        )

        #expect(!succeeded)
        #expect(!fixture.modelContext.hasChanges)
        #expect(ReadStateSync.fetchArticleState(
            forURLString: article.url.absoluteString,
            in: fixture.modelContext
        )?.isRead == false)
        #expect(appState.currentArticle?.isRead == false)
        #expect(PersistenceIssueCenter.shared.activeIssue?.operation == "update read state")
        PersistenceIssueCenter.shared.dismiss()
    }

    @Test func failedProgressSaveReturnsNilAndRestoresStoredProgress() throws {
        let article = Article(id: "progress-failure", title: "Progress Failure")
        let fixture = try makeReadOnlyModelContext { context in
            let state = ArticleState(
                articleTitle: article.title,
                articleURL: article.url
            )
            state.readingProgress = 0.25
            context.insert(state)
        }
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        PersistenceIssueCenter.shared.dismiss()

        let persisted = ReadStateSync.updateReadingProgress(
            0.75,
            for: article,
            in: fixture.modelContext
        )

        #expect(persisted == nil)
        #expect(!fixture.modelContext.hasChanges)
        #expect(approximatelyEqual(ReadStateSync.fetchArticleState(
            forURLString: article.url.absoluteString,
            in: fixture.modelContext
        )?.readingProgress, 0.25))
        #expect(PersistenceIssueCenter.shared.activeIssue?.operation == "update reading progress")
        PersistenceIssueCenter.shared.dismiss()
    }

    @Test func failedCompletionDoesNotAdvanceCoordinatorOrLiveProgress() throws {
        let article = Article(id: "completion-failure", title: "Completion Failure")
        let fixture = try makeReadOnlyModelContext { context in
            let state = ArticleState(
                articleTitle: article.title,
                articleURL: article.url,
                isRead: false
            )
            state.readingProgress = 0.20
            context.insert(state)
        }
        defer { try? FileManager.default.removeItem(at: fixture.directoryURL) }
        let appState = AppState(persistenceMode: .ephemeral)
        appState.openArticle(article)
        var coordinator = ReaderProgressCoordinator()
        coordinator.bootstrapFromPersisted(
            0.20,
            articleTitle: article.title,
            appState: appState,
            now: 10
        )
        PersistenceIssueCenter.shared.dismiss()

        let completed = coordinator.markAsCompleted(
            for: article,
            in: fixture.modelContext,
            appState: appState,
            now: 20
        )

        #expect(!completed)
        #expect(approximatelyEqual(coordinator.latestReadingProgress, 0.20))
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 0.20))
        #expect(appState.currentArticle?.isRead == false)
        PersistenceIssueCenter.shared.dismiss()
    }

    @Test func savedArticleReadStateSyncReportsOnlyRealMutations() throws {
        let modelContext = try makeInMemoryModelContext()
        let list = ReadingList(name: "Inbox")
        let savedArticle = SavedArticle(title: "Ada Lovelace", list: list)
        savedArticle.isRead = false
        list.articles = [savedArticle]
        modelContext.insert(list)
        modelContext.insert(savedArticle)

        #expect(!ReadStateSync.syncSavedArticles(
            title: savedArticle.title,
            isRead: false,
            in: modelContext
        ))
        #expect(ReadStateSync.syncSavedArticles(
            title: savedArticle.title,
            isRead: true,
            in: modelContext
        ))
        #expect(savedArticle.isRead)
        #expect(!ReadStateSync.syncSavedArticles(
            title: savedArticle.title,
            isRead: true,
            in: modelContext
        ))
    }

    private func makeInMemoryModelContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: ArticleState.self,
            Tag.self,
            ReadingList.self,
            SavedArticle.self,
            configurations: configuration
        )
        return ModelContext(container)
    }

    private func makeReadOnlyModelContext(
        seed: (ModelContext) throws -> Void
    ) throws -> (modelContext: ModelContext, directoryURL: URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "MacWiki-ReaderStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let storeURL = directoryURL.appending(path: "ReaderState.store")
        let schema = Schema([
            ArticleState.self,
            Tag.self,
            ReadingList.self,
            SavedArticle.self
        ])

        do {
            let writableConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
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

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }
}
