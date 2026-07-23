import Foundation
import Testing

@testable import MacWiki

struct DiscoverPageViewsPresentationContextTests {
    @Test func cachedInitialRangeDoesNotReloadUntilTheSelectionChanges() {
        var state = DiscoverPageViewsLoadState(initialPointCount: 30)

        #expect(!state.needsLoad(selectedRange: .month, hasPulse: true))
        #expect(state.needsLoad(selectedRange: .quarter, hasPulse: true))
        #expect(state.needsLoad(selectedRange: .month, hasPulse: false))

        state.recordLoad(for: .quarter)
        #expect(!state.needsLoad(selectedRange: .quarter, hasPulse: true))
    }

    @Test func missingOrEmptyInitialPulseRequiresItsFirstLoad() {
        let missing = DiscoverPageViewsLoadState(initialPointCount: nil)
        let empty = DiscoverPageViewsLoadState(initialPointCount: 0)

        #expect(missing.needsLoad(selectedRange: .month, hasPulse: false))
        #expect(empty.needsLoad(selectedRange: .week, hasPulse: true))
    }

    @Test func changingRangeDiscardsThePriorRangePulseBeforeLoading() {
        let cachedMonth = DiscoverPageViewsLoadState(initialPointCount: 30)
        let missing = DiscoverPageViewsLoadState(initialPointCount: nil)

        #expect(!cachedMonth.shouldDiscardPulse(beforeLoading: .month))
        #expect(cachedMonth.shouldDiscardPulse(beforeLoading: .quarter))
        #expect(!missing.shouldDiscardPulse(beforeLoading: .quarter))
    }

    @Test func maxRangeUsesContinuousHistoryEndingAtToday() {
        let calendar = utcCalendar
        let selectedDate = calendar.date(from: DateComponents(year: 2020, month: 5, day: 8, hour: 18))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 9))!
        let context = DiscoverPageViewsPresentationContext(
            selectedDate: selectedDate,
            selectedRange: .max,
            now: now,
            calendar: calendar
        )

        #expect(context.historyMode == .continuousToPresent)
        #expect(context.selectedDate == calendar.date(from: DateComponents(year: 2020, month: 5, day: 8)))
        #expect(context.selectionAnchorDate == calendar.date(from: DateComponents(year: 2020, month: 5, day: 8)))
        #expect(context.historyEndDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 11)))
        #expect(context.allTimeHighDaysEndDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 11)))
        #expect(context.recencySectionTitle == "Latest Days")
    }

    @Test func monthRangeStaysRelativeToSelectedTimeMachineDate() {
        let calendar = utcCalendar
        let selectedDate = calendar.date(from: DateComponents(year: 2020, month: 5, day: 8, hour: 18))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 9))!
        let context = DiscoverPageViewsPresentationContext(
            selectedDate: selectedDate,
            selectedRange: .month,
            now: now,
            calendar: calendar
        )

        #expect(context.historyMode == .selectedDateRelative)
        #expect(context.historyEndDate == calendar.date(from: DateComponents(year: 2020, month: 5, day: 8)))
        #expect(context.selectionAnchorDate == context.historyEndDate)
        #expect(context.requestedDays == 30)
        #expect(context.recencySectionTitle == "Recent Days")
    }

    @Test func allTimeHighDaysRemainContinuousForRelativeRanges() {
        let calendar = utcCalendar
        let selectedDate = calendar.date(from: DateComponents(year: 2020, month: 5, day: 8))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 4, day: 11, hour: 9))!
        let context = DiscoverPageViewsPresentationContext(
            selectedDate: selectedDate,
            selectedRange: .year,
            now: now,
            calendar: calendar
        )

        #expect(context.historyMode == .selectedDateRelative)
        #expect(context.historyEndDate == selectedDate)
        #expect(context.allTimeHighDaysEndDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 11)))
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}
