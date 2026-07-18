import Foundation

enum HighlightDisplayFilter {
    static func visibleHighlights(
        from highlights: [Highlight],
        showStaleHighlights: Bool,
        showArchivedHighlights: Bool
    ) -> [Highlight] {
        highlights.filter { highlight in
            guard !isCitationNoise(highlight) else { return false }
            if highlight.isArchived {
                return showArchivedHighlights
            }
            if !showStaleHighlights && highlight.isStale {
                return false
            }
            return true
        }
    }

    static func visibleHighlights(
        from highlights: [InspectorHighlightSnapshot],
        showStaleHighlights: Bool,
        showArchivedHighlights: Bool
    ) -> [InspectorHighlightSnapshot] {
        highlights.filter { highlight in
            guard !isCitationNoise(
                text: highlight.text,
                sectionTitle: highlight.sectionTitle
            ) else { return false }
            if highlight.isArchived {
                return showArchivedHighlights
            }
            if !showStaleHighlights && highlight.isStale {
                return false
            }
            return true
        }
    }

    static func isCitationNoise(_ highlight: Highlight) -> Bool {
        isCitationNoise(text: highlight.text, sectionTitle: highlight.sectionTitle)
    }

    static func isCitationNoise(text rawText: String, sectionTitle rawSectionTitle: String?) -> Bool {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let lowercasedText = text.lowercased()
        if lowercasedText.contains("cite.citation")
            || lowercasedText.contains("mw-parser-output")
            || lowercasedText.contains(".mw-parser-output")
            || lowercasedText.contains("cs1-")
            || lowercasedText.contains("background:url")
            || lowercasedText.contains("background:")
            || lowercasedText.contains("font-size:")
            || lowercasedText.contains("{{cite") {
            return true
        }

        let sectionTitle = rawSectionTitle?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let isCitationSection = [
            "references",
            "notes",
            "footnotes",
            "bibliography",
            "citations",
            "external links"
        ].contains(sectionTitle)

        let isBareReferenceMarker = HighlightNoteText.displayText(for: text).isEmpty
        if isBareReferenceMarker {
            return true
        }

        let startsLikeCitation = text.range(
            of: #"^(\[\d+\]|\d+\.|\^)"#,
            options: .regularExpression
        ) != nil
        let citationSignals = [
            "retrieved",
            "archived",
            "isbn",
            "doi:",
            "http://",
            "https://",
            "publisher",
            "journal"
        ].filter { lowercasedText.contains($0) }.count

        if startsLikeCitation && citationSignals > 0 {
            return true
        }

        return isCitationSection && citationSignals >= 2
    }
}
