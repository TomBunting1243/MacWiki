import Foundation
import SwiftUI
import Testing

@testable import MacWiki

@MainActor
struct DiscoverScreenModelTests {
    @Test func selectedDateChangeQueuesDebouncedLoadAndDismissesSearchPopover() async {
        let calendar = utcCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 11))!
        let store = DiscoverFeedStore()
        var queuedLoads: [(referenceDate: Date, forceRefresh: Bool)] = []

        let model = DiscoverScreenModel(
            discoverFeedStore: store,
            calendar: calendar,
            now: { now },
            loadDebounceDelay: .milliseconds(5),
            timeTravelSkeletonDelay: .milliseconds(5),
            sleep: { _ in },
            queueLoadAction: { referenceDate, forceRefresh in
                queuedLoads.append((referenceDate, forceRefresh))
            }
        )

        model.selectedDiscoverDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 3, hour: 19))!
        model.presentSearchResultPageViewsPopover(rowKey: "search:1", title: "Ada Lovelace")

        let loadTask = model.handleSelectedDateChange(isSearchActive: false)
        await loadTask?.value

        #expect(queuedLoads.count == 1)
        #expect(queuedLoads.first?.forceRefresh == false)
        #expect(
            queuedLoads.first?.referenceDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 3))
        )
        #expect(model.activeSearchResultPageViewsPopover == nil)
    }

    @Test func refreshDiscoverLoadsImmediatelyAndIncrementsGeneration() {
        let calendar = utcCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 11))!
        let store = DiscoverFeedStore()
        var queuedLoads: [(referenceDate: Date, forceRefresh: Bool)] = []

        let model = DiscoverScreenModel(
            discoverFeedStore: store,
            calendar: calendar,
            now: { now },
            queueLoadAction: { referenceDate, forceRefresh in
                queuedLoads.append((referenceDate, forceRefresh))
            }
        )

        model.selectedDiscoverDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 18))!
        model.refreshDiscover()

        #expect(model.discoverRefreshGeneration == 1)
        #expect(queuedLoads.count == 1)
        #expect(queuedLoads.first?.forceRefresh == true)
        #expect(
            queuedLoads.first?.referenceDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))
        )
    }

    @Test func delayedSkeletonTracksStaleLoadingState() async {
        let calendar = utcCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 11))!
        let store = DiscoverFeedStore()
        store.feed = discoverFeed(dateKey: "2026/04/08")
        store.isLoading = true

        let model = DiscoverScreenModel(
            discoverFeedStore: store,
            calendar: calendar,
            now: { now },
            timeTravelSkeletonDelay: .milliseconds(5),
            sleep: { _ in
            }
        )

        model.selectedDiscoverDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 8))!
        let skeletonTask = model.updateTimeTravelSkeletonVisibility(reduceMotion: true)

        #expect(model.shouldQueueTimeTravelSkeleton == true)
        #expect(model.shouldShowDelayedTimeTravelSkeleton == false)

        await skeletonTask?.value

        #expect(model.shouldShowDelayedTimeTravelSkeleton == true)
        #expect(model.showsTimeTravelSkeleton == true)

        store.isLoading = false
        model.updateTimeTravelSkeletonVisibility(reduceMotion: true)

        #expect(model.shouldShowDelayedTimeTravelSkeleton == false)
        #expect(model.showsTimeTravelSkeleton == false)
    }

    @Test func timeMachineControlsUseImmediateScanningWithoutForcingTheSkeleton() throws {
        let source = try repositorySource(
            "Sources/MacWiki/Views/Home/Discover/DiscoverTimeMachineStageView.swift"
        )

        #expect(source.contains("isScanning: screenModel.shouldQueueTimeTravelSkeleton"))
        #expect(source.contains("showsTimeTravelSkeleton: showsTimeTravelSkeleton"))
    }

    @Test func steppingForwardClampsToTodayAndPopoverDismissalIsScoped() {
        let calendar = utcCalendar
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 9, hour: 11))!
        let model = DiscoverScreenModel(
            calendar: calendar,
            now: { now }
        )

        model.selectedDiscoverDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 8, hour: 12))!
        model.presentSearchResultPageViewsPopover(rowKey: "row-1", title: "Grace Hopper")

        model.shiftDiscoverDate(days: 3)
        model.dismissSearchResultPageViewsPopover(for: "row-2")

        #expect(model.selectedDiscoverDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 9)))
        #expect(model.activeSearchResultPageViewsPopover?.rowKey == "row-1")

        model.dismissSearchResultPageViewsPopover(for: "row-1")

        #expect(model.activeSearchResultPageViewsPopover == nil)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func repositorySource(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private func discoverFeed(dateKey: String) -> WikipediaService.DiscoverFeed {
        WikipediaService.DiscoverFeed(
            dateKey: dateKey,
            dateLabel: "Stub",
            featuredArticle: nil,
            featuredImage: nil,
            newsStories: [],
            inTheNews: [],
            trending: [],
            onThisDay: [],
            onThisDaySelected: [],
            onThisDayBirths: [],
            onThisDayDeaths: [],
            holidays: [],
            didYouKnow: []
        )
    }
}
