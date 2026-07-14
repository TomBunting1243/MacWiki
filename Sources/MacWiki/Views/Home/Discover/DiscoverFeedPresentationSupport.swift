import SwiftUI

extension DiscoverFeedSections {
    func mostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        trendPulseStore.pulse(for: result.title)
    }

    func todayMostReadPulse(for result: WikipediaService.SearchResult) -> WikipediaService.TrendPulse? {
        todayTrendPulseStore.pulse(for: result.title)
    }

    func allTimeMostReadEntry(
        for result: WikipediaService.SearchResult
    ) -> WikipediaService.AllTimeMostReadEntry? {
        allTimeMostReadByTitleKey[ReadStateSync.normalizedTitle(result.title)]
    }

    func mostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        if let allTimeViews = allTimeMostReadEntry(for: result)?.totalViews {
            return "\(abbreviatedViewCount(allTimeViews)) all-time"
        }
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "All-time loading…" : "All-time unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    func mostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = mostReadPulse(for: result) else {
            return trendPulseStore.isLoading ? "Loading recent pulse…" : "Recent pulse unavailable"
        }
        return ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "No delta yet",
            suffix: "recent"
        )
    }

    func mostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = mostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    func todayMostReadPrimaryStat(for result: WikipediaService.SearchResult) -> String {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? "Views loading…" : "Views unavailable"
        }
        return "\(abbreviatedViewCount(pulse.latestViews)) views"
    }

    func todayMostReadSecondaryStat(for result: WikipediaService.SearchResult) -> String? {
        guard let pulse = todayMostReadPulse(for: result) else {
            return todayTrendPulseStore.isLoading ? nil : "No trend data"
        }
        return ArticlePresentationFormatter.pageViewDeltaText(
            latestViews: pulse.latestViews,
            previousViews: pulse.previousViews,
            fallback: "No delta yet"
        )
    }

    func todayMostReadStatTint(for result: WikipediaService.SearchResult) -> Color {
        guard let pulse = todayMostReadPulse(for: result),
              let fraction = trendDeltaFraction(for: pulse) else {
            return .secondary
        }

        if fraction > 0 { return Color.green.opacity(0.85) }
        if fraction < 0 { return Color.red.opacity(0.8) }
        return .secondary
    }

    func trendDeltaFraction(for pulse: WikipediaService.TrendPulse) -> Double? {
        guard let previous = pulse.previousViews, previous > 0 else { return nil }
        return Double(pulse.latestViews - previous) / Double(previous)
    }

    func formattedWordCount(_ wordCount: Int) -> String {
        ArticlePresentationFormatter.wordCountText(wordCount)
    }

    func estimatedReadingTimeText(for wordCount: Int) -> String {
        ArticlePresentationFormatter.readingTimeText(forWordCount: wordCount)
    }

    func formattedReadingDuration(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainderMinutes = minutes % 60
        if remainderMinutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remainderMinutes)m"
    }

    static let featuredFeedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter
    }()

    static let timeMachineTargetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    @ViewBuilder
    func discoverContextMenu(
        for result: WikipediaService.SearchResult,
        onShowPageViews: (() -> Void)? = nil
    ) -> some View {
        SearchResultContextMenuContent(
            result: result,
            allLists: allLists,
            allLabels: allLabels,
            allTags: allTags,
            onOpen: { inNewTab in
                onOpen(result, inNewTab)
            },
            onShowPageViews: onShowPageViews
        )
    }
}
