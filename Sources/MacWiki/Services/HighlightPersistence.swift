import Foundation
import SwiftData

/// Owns the transactional boundary for creating and updating Reader highlights.
///
/// Reader highlighting has multiple UI surfaces. Keeping their mutations here prevents any of
/// them from publishing optimistic state before SwiftData confirms the highlight was saved.
@MainActor
enum HighlightPersistence {
    static func create(
        from selection: TextSelectionData,
        articleTitle: String,
        color: HighlightColor,
        note: String?,
        in modelContext: ModelContext
    ) -> Highlight? {
        let highlight = Highlight(
            text: selection.text,
            articleTitle: articleTitle,
            elementPath: selection.elementPath,
            startOffset: selection.startOffset,
            length: selection.length,
            contextBefore: selection.contextBefore,
            contextAfter: selection.contextAfter,
            sectionTitle: selection.sectionTitle,
            color: color
        )
        highlight.note = note
        modelContext.insert(highlight)

        guard modelContext.saveReportingFailure(operation: "create the highlight") else {
            return nil
        }
        return highlight
    }

    @discardableResult
    static func updateColor(
        of highlight: Highlight,
        to color: HighlightColor,
        in modelContext: ModelContext
    ) -> Bool {
        highlight.color = color
        highlight.updatedAt = Date()
        return modelContext.saveReportingFailure(operation: "change the highlight color")
    }
}
