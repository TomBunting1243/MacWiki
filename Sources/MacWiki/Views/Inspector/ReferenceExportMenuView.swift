import SwiftUI

struct ReferenceExportMenuView: View {
    let selectionCount: Int
    let selectedSections: [ArticleReferenceSection]
    let allSections: [ArticleReferenceSection]

    var body: some View {
        Menu {
            menuContent
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                Text("Export")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gray.opacity(0.12), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.8)
            }
        }
        .menuStyle(.borderlessButton)
    }

    private var menuContent: some View {
        Group {
            if selectionCount > 0 {
                Text("Selected")
                    .font(.caption.weight(.semibold))
                exportMenuItems(for: selectedSections)
                Divider()
            }

            Text("All References")
                .font(.caption.weight(.semibold))
            exportMenuItems(for: allSections)
        }
    }

    @ViewBuilder
    private func exportMenuItems(for exportSections: [ArticleReferenceSection]) -> some View {
        Button("Copy as Plain Text") {
            ReferenceListHelpers.copyReferences(format: .plainText, sections: exportSections)
        }

        Button("Copy as Markdown") {
            ReferenceListHelpers.copyReferences(format: .markdown, sections: exportSections)
        }

        Button("Copy as HTML") {
            ReferenceListHelpers.copyReferences(format: .html, sections: exportSections)
        }

        Divider()

        ShareLink(item: exportPayload(for: .plainText, sections: exportSections)) {
            Text("Share as Plain Text")
        }

        ShareLink(item: exportPayload(for: .markdown, sections: exportSections)) {
            Text("Share as Markdown")
        }

        ShareLink(item: exportPayload(for: .html, sections: exportSections)) {
            Text("Share as HTML")
        }
    }

    private func exportPayload(
        for format: ReferenceExportFormat,
        sections: [ArticleReferenceSection]
    ) -> String {
        ReferenceExportFormatter.payload(
            for: sections,
            format: format,
            includeSectionHeaders: true
        )
    }
}
