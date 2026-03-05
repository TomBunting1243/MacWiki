import Foundation

/// Helper to parse Wikipedia Infobox HTML
enum InfoboxParser {
    
    struct MetadataItem: Identifiable, Equatable {
        let id = UUID()
        let label: String
        let value: String
        
        // Custom equality ignoring UUID
        static func == (lhs: MetadataItem, rhs: MetadataItem) -> Bool {
            return lhs.label == rhs.label && lhs.value == rhs.value
        }
    }
    
    static func extractMetadata(
        from html: String,
        maxScanWindow: Int? = nil,
        maxRows: Int? = nil,
        maxItems: Int? = nil
    ) -> [MetadataItem] {
        var items: [MetadataItem] = []
        
        guard let range = html.range(of: "<table class=\"infobox", options: .caseInsensitive) else {
            return []
        }

        let scanWindowEnd: String.Index = {
            guard let maxScanWindow else { return html.endIndex }
            return html.index(range.lowerBound, offsetBy: maxScanWindow, limitedBy: html.endIndex) ?? html.endIndex
        }()

        guard let endRange = html.range(
            of: "</table>",
            options: .caseInsensitive,
            range: range.lowerBound..<scanWindowEnd
        ) else {
            return []
        }
        
        let tableContent = String(html[range.lowerBound..<endRange.upperBound])
        if let maxScanWindow, tableContent.utf8.count > maxScanWindow {
            return []
        }

        let rows = tableContent.components(separatedBy: "<tr")
        let rowSequence = rows.dropFirst()

        for row in rowSequence.prefix(maxRows ?? rowSequence.count) {
            guard let thStart = row.range(of: "<th"),
                  let thEnd = row.range(of: "</th>"),
                  let tdStart = row.range(of: "<td"),
                  let tdEnd = row.range(of: "</td>") else {
                continue
            }
            
            // Convert to String immediately
            let rawLabelContent = String(row[thStart.upperBound..<thEnd.lowerBound])
            let rawValueContent = String(row[tdStart.upperBound..<tdEnd.lowerBound])
            
            guard let labelContentStart = findTagEndIndex(in: rawLabelContent),
                  let valueContentStart = findTagEndIndex(in: rawValueContent) else {
                continue
            }
            
            let rawLabel = String(rawLabelContent[labelContentStart...])
            let rawValue = String(rawValueContent[valueContentStart...])
            
            // Strip markdown links from labels so headers display cleanly
            let label = truncateMetadataField(
                rawLabel
                    .processingMetadataHTML()
                    .strippingMarkdownLinks()
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: 180
            )
            let value = truncateMetadataField(
                rawValue
                    .processingMetadataHTML()
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                maxLength: 8_000
            )
            
            if !label.isEmpty && !value.isEmpty {
                items.append(MetadataItem(label: label, value: value))
                if let maxItems, items.count >= maxItems {
                    break
                }
            }
        }
        
        return items
    }
    
    static func findTagEndIndex(in text: String) -> String.Index? {
        var inQuote = false
        var quoteChar: Character?
        var escapeNext = false
        
        for (index, char) in text.enumerated() {
            if escapeNext {
                escapeNext = false
                continue
            }
            
            if char == "\\" {
                escapeNext = true
                continue
            }
            
            if let q = quoteChar {
                if char == q {
                    inQuote = false
                    quoteChar = nil
                }
            } else if char == "\"" || char == "'" {
                inQuote = true
                quoteChar = char
            } else if char == ">" && !inQuote {
                return text.index(text.startIndex, offsetBy: index + 1)
            }
        }
        return nil
    }

    private static func truncateMetadataField(_ value: String, maxLength: Int) -> String {
        guard maxLength > 0 else { return "" }
        guard value.count > maxLength else { return value }
        let end = value.index(value.startIndex, offsetBy: maxLength)
        let truncated = value[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return truncated.isEmpty ? "" : "\(truncated)…"
    }
}
