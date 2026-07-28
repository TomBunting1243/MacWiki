import Testing

@testable import MacWiki

struct SidebarDiscoverFeedPresentationTests {
    @Test func retainedEditionFailureShowsWarningWithoutLoadingStatus() {
        let presentation = SidebarDiscoverFeedPresentation(
            hasVisibleFeed: true,
            isLoadingSelectedDate: false,
            errorMessage: "The selected edition could not be loaded."
        )

        #expect(presentation.showsRetainedEditionWarning)
        #expect(!presentation.showsSelectedDateLoadingStatus)
    }

    @Test func selectedDateLoadingStatusDoesNotDependOnTimeMachineControlVisibility() {
        let presentation = SidebarDiscoverFeedPresentation(
            hasVisibleFeed: true,
            isLoadingSelectedDate: true,
            errorMessage: nil
        )

        #expect(presentation.showsSelectedDateLoadingStatus)
        #expect(!presentation.showsRetainedEditionWarning)
    }

    @Test func initialFailureDoesNotClaimThatAnEditionWasRetained() {
        let presentation = SidebarDiscoverFeedPresentation(
            hasVisibleFeed: false,
            isLoadingSelectedDate: false,
            errorMessage: "Discover is unavailable."
        )

        #expect(!presentation.showsRetainedEditionWarning)
        #expect(!presentation.showsSelectedDateLoadingStatus)
    }

}
