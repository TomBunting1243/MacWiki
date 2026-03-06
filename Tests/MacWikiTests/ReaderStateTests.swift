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
        let appState = AppState()
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
        let appState = AppState()
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
        let appState = AppState()
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
        let appState = AppState()
        let modelContext = try makeInMemoryModelContext()
        let article = Article(id: "Turing", title: "Alan Turing")
        var coordinator = ReaderProgressCoordinator()

        coordinator.markAsCompleted(for: article, in: modelContext, appState: appState, now: 500)

        let state = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext)
        #expect(state != nil)
        #expect(state?.isRead == true)
        #expect(approximatelyEqual(state?.readingProgress, 1))
        #expect(approximatelyEqual(coordinator.latestReadingProgress, 1))
        #expect(approximatelyEqual(appState.liveReadingProgress(forTitle: article.title), 1))
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

    private func approximatelyEqual(_ lhs: Double?, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) <= tolerance
    }
}
