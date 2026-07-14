import Foundation
import Observation
import SwiftUI

@Observable @MainActor
final class DiscoverScreenModel {
    static let defaultLoadDebounceDelay: Duration = .milliseconds(170)

    let discoverFeedStore: DiscoverFeedStore

    var selectedDiscoverDate: Date
    var discoverRefreshGeneration = 0
    var activeSearchResultPageViewsPopover: DiscoverInlinePageViewsPopoverPayload?
    var isTimeMachineDatePickerPresented = false
    var timeMachineLensLastDragX: CGFloat?
    var timeMachineLensDragAccumulatedX: CGFloat = 0

    private let calendar: Calendar
    private let now: @MainActor () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let queueLoadAction: @MainActor (Date, Bool) -> Void
    private let cancelAction: @MainActor () -> Void
    private let loadDebounceDelay: Duration

    @ObservationIgnored private var discoverDateLoadTask: Task<Void, Never>?

    init(
        discoverFeedStore: DiscoverFeedStore = DiscoverFeedStore(),
        calendar: Calendar = .current,
        now: @escaping @MainActor () -> Date = Date.init,
        loadDebounceDelay: Duration = DiscoverScreenModel.defaultLoadDebounceDelay,
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        },
        queueLoadAction: (@MainActor (Date, Bool) -> Void)? = nil,
        cancelAction: (@MainActor () -> Void)? = nil
    ) {
        self.discoverFeedStore = discoverFeedStore
        self.calendar = calendar
        self.now = now
        self.loadDebounceDelay = loadDebounceDelay
        self.sleep = sleep
        self.queueLoadAction = queueLoadAction ?? { referenceDate, forceRefresh in
            discoverFeedStore.queueLoad(referenceDate: referenceDate, forceRefresh: forceRefresh)
        }
        self.cancelAction = cancelAction ?? {
            discoverFeedStore.cancel()
        }
        self.selectedDiscoverDate = now()
    }

    var discoverReferenceDate: Date {
        calendar.startOfDay(for: selectedDiscoverDate)
    }

    /// The selected date is loading while the last complete edition remains visible.
    /// Keeping that edition mounted avoids collapsing the magazine into a synthetic
    /// placeholder layout during an ordinary Time Machine navigation.
    var isLoadingSelectedDate: Bool {
        guard discoverFeedStore.isLoading else { return false }
        guard let visibleFeed = discoverFeedStore.feed else { return false }
        return visibleFeed.dateKey != selectedDiscoverDateKey
    }

    var canStepDiscoverDateForward: Bool {
        discoverReferenceDate < calendar.startOfDay(for: now())
    }

    var isDiscoverDateToday: Bool {
        calendar.isDate(discoverReferenceDate, inSameDayAs: now())
    }

    var discoverTimeMachineDateLabel: String {
        Self.timeMachineCompactDateFormatter.string(from: discoverReferenceDate)
    }

    @discardableResult
    func handleSelectedDateChange(isSearchActive: Bool) -> Task<Void, Never>? {
        guard !isSearchActive else { return nil }
        dismissSearchResultPageViewsPopover()
        return queueDiscoverLoadDebounced()
    }

    func queueInitialLoad() {
        queueDiscoverLoadDebounced(delay: .zero)
    }

    func refreshDiscover() {
        queueDiscoverLoadDebounced(forceRefresh: true, delay: .zero)
        discoverRefreshGeneration += 1
    }

    @discardableResult
    func queueDiscoverLoadDebounced(
        forceRefresh: Bool = false,
        delay: Duration? = nil
    ) -> Task<Void, Never>? {
        discoverDateLoadTask?.cancel()
        let effectiveDelay = delay ?? loadDebounceDelay
        if forceRefresh || effectiveDelay <= .zero {
            queueLoadAction(discoverReferenceDate, forceRefresh)
            return nil
        }
        let task = Task { @MainActor in
            await sleep(effectiveDelay)
            guard !Task.isCancelled else { return }
            queueLoadAction(discoverReferenceDate, forceRefresh)
        }
        discoverDateLoadTask = task
        return task
    }

    func handleDisappear() {
        discoverDateLoadTask?.cancel()
        discoverDateLoadTask = nil
        resetTimeMachineLensDrag()
        dismissSearchResultPageViewsPopover()
        cancelAction()
    }

    func shiftDiscoverDate(days: Int) {
        let today = calendar.startOfDay(for: now())
        let shifted = calendar.date(byAdding: .day, value: days, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    func shiftDiscoverDate(years: Int) {
        let today = calendar.startOfDay(for: now())
        let shifted = calendar.date(byAdding: .year, value: years, to: discoverReferenceDate) ?? discoverReferenceDate
        selectedDiscoverDate = min(shifted, today)
    }

    func stepTimeMachineLensByDrag(deltaX: CGFloat) {
        timeMachineLensDragAccumulatedX += deltaX
        let threshold: CGFloat = 18

        while abs(timeMachineLensDragAccumulatedX) >= threshold {
            let isForward = timeMachineLensDragAccumulatedX > 0
            shiftDiscoverDate(days: isForward ? 1 : -1)
            timeMachineLensDragAccumulatedX += isForward ? -threshold : threshold
        }
    }

    func resetTimeMachineLensDrag() {
        timeMachineLensLastDragX = nil
        timeMachineLensDragAccumulatedX = 0
    }

    func presentSearchResultPageViewsPopover(rowKey: String, title: String) {
        activeSearchResultPageViewsPopover = DiscoverInlinePageViewsPopoverPayload(
            rowKey: rowKey,
            title: title
        )
    }

    func dismissSearchResultPageViewsPopover() {
        activeSearchResultPageViewsPopover = nil
    }

    func dismissSearchResultPageViewsPopover(for rowKey: String) {
        guard activeSearchResultPageViewsPopover?.rowKey == rowKey else { return }
        activeSearchResultPageViewsPopover = nil
    }

    private var selectedDiscoverDateKey: String {
        Self.discoverFeedDateFormatter.string(from: discoverReferenceDate)
    }

    private static let discoverFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    private static let timeMachineCompactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }()
}
