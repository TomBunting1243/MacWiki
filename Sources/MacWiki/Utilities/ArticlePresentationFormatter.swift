import Foundation

enum ArticlePresentationFormatter {
    private static let wordsPerMinute = 220.0
    private static let estimatedCharactersPerWord = 5

    static func wordCountText(_ wordCount: Int) -> String {
        let formatted = NumberFormatter.localizedString(
            from: NSNumber(value: wordCount),
            number: .decimal
        )
        return "\(formatted) words"
    }

    static func estimatedWordCountText(
        fromExtract extract: String?,
        minimumCharacters: Int = 50
    ) -> String? {
        guard let extract, extract.count > minimumCharacters else { return nil }
        return wordCountText(extract.count / estimatedCharactersPerWord)
    }

    static func wordCountText(
        wordCount: Int?,
        fallbackExtract extract: String?,
        allowsEstimate: Bool = true
    ) -> String? {
        if let wordCount {
            return wordCountText(wordCount)
        }
        guard allowsEstimate else { return nil }
        return estimatedWordCountText(fromExtract: extract)
    }

    static func readingMinutes(forWordCount wordCount: Int) -> Int {
        max(1, Int((Double(wordCount) / wordsPerMinute).rounded(.up)))
    }

    static func readingTimeText(forWordCount wordCount: Int) -> String {
        "\(readingMinutes(forWordCount: wordCount)) min read"
    }

    static func pageViewDeltaFraction(latestViews: Int, previousViews: Int?) -> Double? {
        guard let previousViews, previousViews > 0 else { return nil }
        return Double(latestViews - previousViews) / Double(previousViews)
    }

    static func pageViewDeltaText(
        latestViews: Int,
        previousViews: Int?,
        fallback: String = "No delta",
        suffix: String? = nil
    ) -> String {
        guard let fraction = pageViewDeltaFraction(
            latestViews: latestViews,
            previousViews: previousViews
        ) else {
            return fallback
        }

        let percent = fraction * 100
        let sign = percent > 0 ? "+" : ""
        let percentText = percent.formatted(.number.precision(.fractionLength(0...1)))

        guard let suffix, !suffix.isEmpty else {
            return "\(sign)\(percentText)%"
        }
        return "\(sign)\(percentText)% \(suffix)"
    }
}
