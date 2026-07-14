import Foundation

enum AppPresentationFormatting {
    static func storageByteCount(
        _ bytes: Int,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        Int64(max(bytes, 0)).formatted(
            ByteCountFormatStyle(
                style: .file,
                allowedUnits: [.kb, .mb, .gb],
                spellsOutZero: true,
                includesActualByteCount: false,
                locale: locale
            )
        )
    }

    static func abbreviatedWeekdayMonthDay(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            baseDateStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .weekday(.abbreviated)
                .month(.abbreviated)
                .day()
        )
    }

    static func abbreviatedMonthDay(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            baseDateStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .month(.abbreviated)
                .day()
        )
    }

    static func longDate(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            baseDateStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .year()
                .month(.wide)
                .day()
        )
    }

    static func abbreviatedDate(
        _ date: Date,
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        date.formatted(
            baseDateStyle(locale: locale, calendar: calendar, timeZone: timeZone)
                .year()
                .month(.abbreviated)
                .day()
        )
    }

    private static func baseDateStyle(
        locale: Locale,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted,
            time: .omitted,
            locale: locale,
            calendar: calendar,
            timeZone: timeZone
        )
    }
}
