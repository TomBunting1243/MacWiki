import Foundation
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

    @Test func directoryHooksStatusOutsideTheTimeMachineVisibilityBranchAndKeepsFeedUsableAfterLoading() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
            ),
            encoding: .utf8
        )
        let discoverSurface = try #require(source.range(of: "func discoverSections() -> some View"))
        let sectionSource = String(source[discoverSurface.lowerBound...])
        let controls = try #require(sectionSource.range(of: "SidebarDiscoverTimeMachineView("))
        let loadingStatus = try #require(
            sectionSource.range(of: "if sidebarDiscoverFeedPresentation.showsSelectedDateLoadingStatus")
        )

        #expect(loadingStatus.lowerBound > controls.lowerBound)
        #expect(sectionSource.contains("isHidden: $discoverSidebarTimeMachineHidden"))
        #expect(sectionSource.contains("SidebarDiscoverRetainedEditionWarning("))
        #expect(sectionSource.contains("queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)"))
        #expect(sectionSource.contains(".allowsHitTesting(!isSidebarTimeTraveling)"))
        #expect(sectionSource.contains(".accessibilityHidden(isSidebarTimeTraveling)"))

        let stateViewsSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverFeedStateViews.swift"
            ),
            encoding: .utf8
        )
        #expect(stateViewsSource.contains("You can keep reading the \\(editionDateLabel) edition."))
        #expect(!stateViewsSource.contains("the (editionDateLabel) edition"))
    }

    private func repositoryRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
