import Testing

@testable import MacWiki

struct DiscoverTodayMostReadPresentationTests {
    @Test func metadataDistinguishesLoadingFailureEmptyAndPopulatedStates() {
        #expect(DiscoverTodayMostReadPresentation.metadata(
            isLoading: true,
            hasFailure: false,
            itemCount: 0
        ) == "Refreshing")
        #expect(DiscoverTodayMostReadPresentation.metadata(
            isLoading: false,
            hasFailure: true,
            itemCount: 0
        ) == "Unavailable")
        #expect(DiscoverTodayMostReadPresentation.metadata(
            isLoading: false,
            hasFailure: false,
            itemCount: 0
        ) == "No ranking today")
        #expect(DiscoverTodayMostReadPresentation.metadata(
            isLoading: false,
            hasFailure: false,
            itemCount: 14
        ) == "14 articles today")
    }

    @Test func placeholderDistinguishesLoadingFailureAndValidEmptyStates() {
        #expect(DiscoverTodayMostReadPresentation.placeholder(
            isLoading: true,
            hasFailure: false
        ) == "Loading today's most read...")
        #expect(DiscoverTodayMostReadPresentation.placeholder(
            isLoading: false,
            hasFailure: true
        ) == "Today's ranking is unavailable right now.")
        #expect(DiscoverTodayMostReadPresentation.placeholder(
            isLoading: false,
            hasFailure: false
        ) == "No articles are ranked today.")
    }

    @Test func failureActionRetriesWithAForcedRefresh() {
        let action = DiscoverTodayMostReadPresentation.failureAction

        #expect(action.kind == .tryAgain)
        #expect(action.forceRefresh)
    }
}
