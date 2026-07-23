import Foundation

enum DiscoverPageViewsHistoryMode: Equatable, Sendable {
    case selectedDateRelative
    case continuousToPresent
}

struct DiscoverPageViewsLoadState: Equatable, Sendable {
    private(set) var loadedRange: ViewsPopoverTimeRange?

    init(initialPointCount: Int?) {
        guard let initialPointCount, initialPointCount > 0 else {
            loadedRange = nil
            return
        }
        loadedRange = ViewsPopoverTimeRange.matching(days: initialPointCount)
    }

    func needsLoad(
        selectedRange: ViewsPopoverTimeRange,
        hasPulse: Bool
    ) -> Bool {
        !hasPulse || loadedRange != selectedRange
    }

    func shouldDiscardPulse(beforeLoading selectedRange: ViewsPopoverTimeRange) -> Bool {
        guard let loadedRange else { return false }
        return loadedRange != selectedRange
    }

    mutating func recordLoad(for selectedRange: ViewsPopoverTimeRange) {
        loadedRange = selectedRange
    }
}

struct DiscoverPageViewsPresentationContext: Equatable, Sendable {
    let selectedDate: Date
    let historyEndDate: Date
    let historyMode: DiscoverPageViewsHistoryMode
    let selectedRange: ViewsPopoverTimeRange
    let requestedDays: Int
    let selectionAnchorDate: Date
    let allTimeHighDaysEndDate: Date

    init(
        selectedDate: Date,
        selectedRange: ViewsPopoverTimeRange,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        let today = calendar.startOfDay(for: now)
        let selectedDay = min(calendar.startOfDay(for: selectedDate), today)
        let historyMode = selectedRange.historyMode
        let historyEndDate: Date
        switch historyMode {
        case .selectedDateRelative:
            historyEndDate = selectedDay
        case .continuousToPresent:
            historyEndDate = today
        }

        self.selectedDate = selectedDay
        self.historyEndDate = historyEndDate
        self.historyMode = historyMode
        self.selectedRange = selectedRange
        self.requestedDays = selectedRange.requestedDays(
            relativeTo: historyEndDate,
            calendar: calendar
        )
        self.selectionAnchorDate = selectedDay
        self.allTimeHighDaysEndDate = today
    }

    var recencySectionTitle: String {
        switch historyMode {
        case .selectedDateRelative:
            return "Recent Days"
        case .continuousToPresent:
            return "Latest Days"
        }
    }
}
