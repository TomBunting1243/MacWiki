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

    @Test func directoryKeepsStatusInTheFeedWhileTimeMachineLivesInThePinnedHeader() throws {
        let source = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
            ),
            encoding: .utf8
        )
        let headerControls = try #require(source.range(of: "private var discoverHeaderControls"))
        let viewOptions = try #require(source.range(of: "private var directoryViewOptionsMenu"))
        let headerSource = String(source[headerControls.lowerBound..<viewOptions.lowerBound])
        let discoverSurface = try #require(source.range(of: "func discoverSections() -> some View"))
        let sectionSource = String(source[discoverSurface.lowerBound...])
        let loadingStatus = try #require(
            sectionSource.range(of: "if sidebarDiscoverFeedPresentation.showsSelectedDateLoadingStatus")
        )

        #expect(loadingStatus.lowerBound > sectionSource.startIndex)
        #expect(headerSource.contains("SidebarDiscoverTimeMachineView("))
        #expect(headerSource.contains(".popover(isPresented: $isSidebarTimeMachinePresented"))
        #expect(headerSource.contains("if !discoverSidebarTimeMachineHidden"))
        #expect(headerSource.contains("private var discoverRefreshButton"))
        #expect(headerSource.contains("Button(\"Refresh\", systemImage: \"arrow.clockwise\""))
        #expect(headerSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(headerSource.contains(".labelStyle(.iconOnly)"))
        #expect(!sectionSource.contains("SidebarDiscoverTimeMachineView("))
        #expect(sectionSource.contains("SidebarDiscoverRetainedEditionWarning("))
        #expect(sectionSource.contains("queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)"))
        #expect(!sectionSource.contains(".allowsHitTesting(!isSidebarTimeTraveling)"))
        #expect(!sectionSource.contains(".accessibilityHidden(isSidebarTimeTraveling)"))
        #expect(source.contains("discoverDateLoadTask?.cancel()"))
        #expect(source.contains("discoverTrendPulseStore.cancel()"))
        #expect(source.contains("SidebarSearchView(model: sidebarSearchModel)\n                    .onAppear"))
        #expect(source.contains("flushScheduledModelContextSave()\n            isSidebarTimeMachinePresented = false"))

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
