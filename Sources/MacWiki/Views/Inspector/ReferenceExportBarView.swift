import SwiftUI

struct ReferenceExportBarView: View {
    let totalCount: Int
    let selectionCount: Int
    let selectedSections: [ArticleReferenceSection]
    let allSections: [ArticleReferenceSection]
    let onClearSelection: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(selectionCount > 0 ? "Selected \(selectionCount)" : "All \(totalCount)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if selectionCount > 0 {
                Button("Clear") {
                    onClearSelection()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            ReferenceExportMenuView(
                selectionCount: selectionCount,
                selectedSections: selectedSections,
                allSections: allSections
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .readerInspectorRoundedSurface(
            cornerRadius: 16,
            material: .ultraThin,
            baseBorderOpacity: 0.08,
            highlightOpacity: 0.10,
            shadowOpacity: 0.12,
            shadowRadius: 10,
            shadowY: 4
        )
    }
}
