import SwiftData

/// Owns the transactional boundary for creating Reader highlights.
///
/// Both the floating selection toolbar and the native WebView context menu create the same
/// model. Keeping that work here prevents either UI surface from publishing optimistic state
/// before SwiftData confirms the highlight was saved.
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
}
