import Foundation

struct ReferenceExportFormatter {
    static func payload(
        for sections: [ArticleReferenceSection],
        format: ReferenceExportFormat,
        includeSectionHeaders: Bool
    ) -> String {
        switch format {
        case .plainText:
            return exportPlainText(for: sections, includeSectionHeaders: includeSectionHeaders)
        case .markdown:
            return exportMarkdown(for: sections, includeSectionHeaders: includeSectionHeaders)
        case .html:
            return exportHTML(for: sections, includeSectionHeaders: includeSectionHeaders)
        }
    }

    private static func exportPlainText(
        for sections: [ArticleReferenceSection],
        includeSectionHeaders: Bool
    ) -> String {
        var lines: [String] = []

        for section in sections {
            if includeSectionHeaders {
                lines.append(section.title)
            }

            for (index, item) in section.items.enumerated() {
                let label = displayLabel(for: item, index: index)
                var line = label.isEmpty ? item.text : "[\(label)] \(item.text)"

                if !item.links.isEmpty {
                    let links = item.links.joined(separator: ", ")
                    line.append(" (\(links))")
                }
                lines.append(line)
            }

            if includeSectionHeaders {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func exportMarkdown(
        for sections: [ArticleReferenceSection],
        includeSectionHeaders: Bool
    ) -> String {
        var lines: [String] = []

        for section in sections {
            if includeSectionHeaders {
                lines.append("## \(section.title)")
            }

            for (index, item) in section.items.enumerated() {
                let label = displayLabel(for: item, index: index)
                var line = label.isEmpty ? "- \(item.text)" : "- [\(label)] \(item.text)"

                if !item.links.isEmpty {
                    let links = item.links.map { "<\($0)>" }.joined(separator: " ")
                    line.append(" \(links)")
                }
                lines.append(line)
            }

            if includeSectionHeaders {
                lines.append("")
            }
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func exportHTML(
        for sections: [ArticleReferenceSection],
        includeSectionHeaders: Bool
    ) -> String {
        var blocks: [String] = []

        for section in sections {
            var items: [String] = []

            for (index, item) in section.items.enumerated() {
                let label = displayLabel(for: item, index: index)
                let labelHTML = label.isEmpty ? "" : "<span class=\"mw-ref-label\">[\(escapeHTML(label))]</span> "
                let bodyHTML = item.html?.isEmpty == false ? item.html! : escapeHTML(item.text)
                items.append("<li>\(labelHTML)\(bodyHTML)</li>")
            }

            let listHTML = "<ul>\(items.joined())</ul>"
            if includeSectionHeaders {
                blocks.append("<h2>\(escapeHTML(section.title))</h2>\n\(listHTML)")
            } else {
                blocks.append(listHTML)
            }
        }

        return blocks.joined(separator: "\n")
    }

    private static func displayLabel(for item: ArticleReferenceItem, index: Int) -> String {
        let trimmed = item.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "\(index + 1)"
    }

    private static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
