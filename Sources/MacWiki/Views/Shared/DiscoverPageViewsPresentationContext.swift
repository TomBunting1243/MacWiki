import Foundation

enum DiscoverPageViewsHistoryMode: Equatable, Sendable {
    case selectedDateRelative
    case continuousToPresent
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
