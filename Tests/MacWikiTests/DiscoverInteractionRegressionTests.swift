import Testing

@testable import MacWiki

struct DiscoverInteractionRegressionTests {
    @Test func searchStatusPrioritizesLoadingAndDistinguishesInitialFromUpdatingResults() {
        let initialSearch = DiscoverSearchStatusPresentation(
            resultCount: 0,
            isLoading: true,
            hasError: true
        )
        let updatingResults = DiscoverSearchStatusPresentation(
            resultCount: 3,
            isLoading: true,
            hasError: false
        )

        #expect(initialSearch == .searching)
        #expect(initialSearch.subtitle == "Searching Wikipedia")
        #expect(updatingResults == .updating(resultCount: 3))
        #expect(updatingResults.subtitle == "3 found · Updating")
    }

    @Test func searchStatusReportsUnavailableOnlyWithoutVisibleResults() {
        let unavailable = DiscoverSearchStatusPresentation(
            resultCount: 0,
            isLoading: false,
            hasError: true
        )
        let retainedResults = DiscoverSearchStatusPresentation(
            resultCount: 2,
            isLoading: false,
            hasError: true
        )

        #expect(unavailable == .unavailable)
        #expect(unavailable.subtitle == "Search unavailable")
        #expect(retainedResults == .matches(resultCount: 2))
        #expect(retainedResults.subtitle == "2 matches")
    }

    @Test func searchStatusUsesSingularAndPluralMatchCopy() {
        let empty = DiscoverSearchStatusPresentation(
            resultCount: 0,
            isLoading: false,
            hasError: false
        )
        let singleMatch = DiscoverSearchStatusPresentation(
            resultCount: 1,
            isLoading: false,
            hasError: false
        )

        #expect(empty == .matches(resultCount: 0))
        #expect(empty.subtitle == "0 matches")
        #expect(singleMatch == .matches(resultCount: 1))
        #expect(singleMatch.subtitle == "1 match")
    }
}
