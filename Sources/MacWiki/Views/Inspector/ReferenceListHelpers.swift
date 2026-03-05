import SwiftUI

@MainActor
enum ReferenceListHelpers {
    static func displayLabel(for item: ArticleReferenceItem, index: Int) -> String {
        let trimmed = item.label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed
        }
        return "\(index + 1)"
    }

    static func filteredSections(
        sections: [ArticleReferenceSection],
        selection: Set<String>
    ) -> [ArticleReferenceSection] {
        sections.compactMap { section in
            let items = section.items.filter { selection.contains($0.id) }
            guard !items.isEmpty else { return nil }
            return ArticleReferenceSection(id: section.id, title: section.title, items: items)
        }
    }

    static func openFirstLink(
        appState: AppState,
        item: ArticleReferenceItem,
        openExternalURL: (URL) -> Void
    ) {
        guard let link = item.links.first,
              let url = URL(string: link) else { return }

        if url.host?.contains("wikipedia.org") == true,
           url.path.hasPrefix("/wiki/") {
            let articlePath = String(url.path.dropFirst(6))
            let title = articlePath.removingPercentEncoding ?? articlePath
            let displayTitle = title.replacingOccurrences(of: "_", with: " ")
            let article = Article(id: displayTitle, title: displayTitle)
            appState.openArticle(article, inNewTab: false)
        } else {
            openExternalURL(url)
        }
    }

    static func copyReferences(
        format: ReferenceExportFormat,
        sections: [ArticleReferenceSection],
        includeSectionHeaders: Bool = true
    ) {
        let payload = ReferenceExportFormatter.payload(
            for: sections,
            format: format,
            includeSectionHeaders: includeSectionHeaders
        )
        _ = SystemBridge.copyText(payload)
    }
}
