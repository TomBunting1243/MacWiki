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
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0.02),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .blendMode(.screen)
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
