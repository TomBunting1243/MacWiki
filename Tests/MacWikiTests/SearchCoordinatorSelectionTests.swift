import Testing

@testable import MacWiki

@MainActor
struct SearchCoordinatorSelectionTests {
    @Test func selectedResultTracksArrowNavigationAndClampsToAvailableResults() {
        let coordinator = SearchCoordinator(
            debounceMilliseconds: 60_000,
            minimumQueryLength: 2,
            supportsTrending: false
        )
        let results = (0..<3).map { index in
            WikipediaService.SearchResult(
                id: "result-\(index)",
                title: "Result \(index)",
                description: nil,
                thumbnailURL: nil
            )
        }

        coordinator.searchText = "results"
        coordinator.searchResults = results

        #expect(coordinator.selectedResult(usingTrendingFallback: false)?.id == "result-0")

        coordinator.moveSelectionDown(usingTrendingFallback: false)
        coordinator.moveSelectionDown(usingTrendingFallback: false)
        coordinator.moveSelectionDown(usingTrendingFallback: false)
        #expect(coordinator.selectedResult(usingTrendingFallback: false)?.id == "result-2")

        coordinator.moveSelectionUp(usingTrendingFallback: false)
        #expect(coordinator.selectedResult(usingTrendingFallback: false)?.id == "result-1")

        coordinator.cancel()
    }
}
