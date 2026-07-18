import Foundation

/// Presentation-only cleanup for the source quote shown in Notes.
///
/// The persisted highlight text remains untouched because WebKit uses that exact
/// source string, together with its surrounding context, to restore the range.
enum HighlightNoteText {
    private static let citationMarkers = try? NSRegularExpression(
        pattern: #"(?:\h*\[(?:\d+(?:\h*[,\-–]\h*\d+)*|[A-Za-z]|(?:note|nb)\h+\d+)\])+"#,
        options: [.caseInsensitive]
    )

    static func displayText(for sourceText: String) -> String {
        guard let citationMarkers else {
            return sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let sourceRange = NSRange(sourceText.startIndex..<sourceText.endIndex, in: sourceText)
        return citationMarkers
            .stringByReplacingMatches(
                in: sourceText,
                options: [],
                range: sourceRange,
                withTemplate: ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
