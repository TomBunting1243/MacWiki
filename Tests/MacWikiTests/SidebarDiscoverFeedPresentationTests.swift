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
        let directorySource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/DirectoryView.swift"
            ),
            encoding: .utf8
        )
        let accessorySource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Columns/DirectoryColumnAccessoryView.swift"
            ),
            encoding: .utf8
        )
        let timeMachineSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverTimeMachineView.swift"
            ),
            encoding: .utf8
        )
        let timeMachineBody = try #require(timeMachineSource.range(of: "var body: some View"))
        let timeMachinePicker = try #require(timeMachineSource.range(of: "private var editionDatePicker"))
        let bodySource = String(
            timeMachineSource[timeMachineBody.lowerBound..<timeMachinePicker.lowerBound]
        )
        let nativeControlsSource = try String(
            contentsOf: repositoryRoot().appendingPathComponent(
                "Sources/MacWiki/Views/Sidebar/Directory/SidebarDiscoverHeaderControls.swift"
            ),
            encoding: .utf8
        )
        let discoverControls = try #require(
            accessorySource.range(of: "private var discoverControls")
        )
        let viewOptions = try #require(
            accessorySource.range(of: "private var viewOptionsMenu")
        )
        let launcherSource = String(
            accessorySource[discoverControls.lowerBound..<viewOptions.lowerBound]
        )
        let discoverSurface = try #require(
            directorySource.range(of: "func discoverSections() -> some View")
        )
        let sectionSource = String(directorySource[discoverSurface.lowerBound...])
        let loadingStatus = try #require(
            sectionSource.range(of: "if sidebarDiscoverFeedPresentation.showsSelectedDateLoadingStatus")
        )

        #expect(loadingStatus.lowerBound > sectionSource.startIndex)
        #expect(accessorySource.contains("SidebarDiscoverTimeMachineView("))
        #expect(accessorySource.contains("@Bindable var columnState: DirectoryColumnState"))
        #expect(accessorySource.contains("SidebarDiscoverHeaderControls("))
        #expect(accessorySource.contains("showsTimeMachine: !discoverTimeMachineHidden"))
        #expect(accessorySource.contains("onRefresh: refreshDiscover"))
        #expect(!launcherSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(!accessorySource.contains(".popover("))
        #expect(accessorySource.contains("longDiscoverDateLabel"))
        #expect(nativeControlsSource.contains("NSSegmentedControl"))
        #expect(nativeControlsSource.contains("NSPopover"))
        #expect(nativeControlsSource.contains("popover.behavior = .transient"))
        #expect(nativeControlsSource.contains("popover.show("))
        #expect(!sectionSource.contains("SidebarDiscoverTimeMachineView("))
        #expect(sectionSource.contains("SidebarDiscoverRetainedEditionWarning("))
        #expect(sectionSource.contains("queueDiscoverLoadDebounced(forceRefresh: true, delayNanoseconds: 0)"))
        #expect(!sectionSource.contains(".allowsHitTesting(!isSidebarTimeTraveling)"))
        #expect(!sectionSource.contains(".accessibilityHidden(isSidebarTimeTraveling)"))
        #expect(directorySource.contains("discoverTrendPulseStore.cancel()"))
        #expect(directorySource.contains("SidebarSearchView("))
        #expect(directorySource.contains("isSearchFieldFocused: Binding("))

        #expect(timeMachineSource.contains("DatePicker("))
        #expect(timeMachineSource.contains(".datePickerStyle(.graphical)"))
        #expect(!timeMachineSource.contains(".datePickerStyle(.field)"))
        #expect(!bodySource.contains("Hide from List Contents"))
        #expect(timeMachineSource.contains("Button(\"Hide from List Contents\""))
        #expect(timeMachineSource.contains("Button(\"Previous Day\", systemImage: \"chevron.left\")"))
        #expect(timeMachineSource.contains("Button(\"Today\", systemImage: \"sun.max\")"))
        #expect(timeMachineSource.contains("Button(\"Next Day\", systemImage: \"chevron.right\")"))
        #expect(timeMachineSource.contains("Menu(\"Jump\", systemImage: \"calendar\")"))
        #expect(timeMachineSource.contains("Button(\"Refresh\", systemImage: \"arrow.clockwise\""))

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
