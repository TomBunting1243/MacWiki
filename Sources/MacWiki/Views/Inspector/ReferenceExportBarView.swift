import SwiftUI

struct ReferenceExportBarView: View {
    let totalCount: Int
    let selectionCount: Int
    let selectedSections: [ArticleReferenceSection]
    let allSections: [ArticleReferenceSection]
    let onClearSelection: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

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
            shape
                .fill(.ultraThinMaterial)
                .overlay {
                    shape
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.04 : 0.025))
                }
                .overlay {
                    shape
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.10),
                                    Color.white.opacity(0.015),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                }
        }
        .overlay {
            shape
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}
