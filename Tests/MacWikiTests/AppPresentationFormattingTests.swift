import Foundation
import Testing

@testable import MacWiki

struct AppPresentationFormattingTests {
    private let gregorian = Calendar(identifier: .gregorian)
    private let utc = TimeZone.gmt
    private let english = Locale(identifier: "en_US")

    @Test func storageByteCountUsesNativeFileUnitsAndClampsInvalidMetrics() {
        #expect(
            AppPresentationFormatting.storageByteCount(-1, locale: english)
                == AppPresentationFormatting.storageByteCount(0, locale: english)
        )
        #expect(AppPresentationFormatting.storageByteCount(999, locale: english) == "1 kB")
        #expect(AppPresentationFormatting.storageByteCount(999_999, locale: english) == "1 MB")
        #expect(AppPresentationFormatting.storageByteCount(1_000_000_000, locale: english) == "1 GB")
    }

    @Test func editorialDateStylesPreserveTheIntendedInformationHierarchy() throws {
        let date = try #require(
            DateComponents(
                calendar: gregorian,
                timeZone: utc,
                year: 2026,
                month: 7,
                day: 14,
                hour: 12
            ).date
        )

        #expect(
            AppPresentationFormatting.abbreviatedWeekdayMonthDay(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: utc
            ) == "Tue, Jul 14"
        )
        #expect(
            AppPresentationFormatting.abbreviatedMonthDay(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: utc
            ) == "Jul 14"
        )
        #expect(
            AppPresentationFormatting.longDate(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: utc
            ) == "July 14, 2026"
        )
        #expect(
            AppPresentationFormatting.abbreviatedDate(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: utc
            ) == "Jul 14, 2026"
        )
    }

    @Test func dateFormattingHonorsTheSuppliedTimeZone() throws {
        let date = try #require(
            DateComponents(
                calendar: gregorian,
                timeZone: utc,
                year: 2026,
                month: 7,
                day: 14,
                hour: 0,
                minute: 30
            ).date
        )
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))

        #expect(
            AppPresentationFormatting.abbreviatedMonthDay(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: utc
            ) == "Jul 14"
        )
        #expect(
            AppPresentationFormatting.abbreviatedMonthDay(
                date,
                locale: english,
                calendar: gregorian,
                timeZone: losAngeles
            ) == "Jul 13"
        )
    }
}
