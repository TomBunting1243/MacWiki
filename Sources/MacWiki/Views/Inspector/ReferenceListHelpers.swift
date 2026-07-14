import SwiftUI

@MainActor
enum ReferenceListHelpers {
    @MainActor
    struct Presentation: Equatable {
        static let empty = Presentation(
            sections: [],
            referenceIDs: [],
            totalCount: 0
        )

        let sections: [ArticleReferenceSection]
        let referenceIDs: Set<String>
        let totalCount: Int

        static func make(from sections: [ArticleReferenceSection]) -> Presentation {
            let visibleSections = ReferenceListHelpers.visibleSections(from: sections)
            var referenceIDs = Set<String>()
            let totalCount = visibleSections.reduce(into: 0) { count, section in
                count += section.items.count
                referenceIDs.formUnion(section.items.lazy.map(\.id))
            }
            return Presentation(
                sections: visibleSections,
                referenceIDs: referenceIDs,
                totalCount: totalCount
            )
        }

        func selectedSections(for selection: Set<String>) -> [ArticleReferenceSection] {
            guard !selection.isEmpty else { return [] }
            return ReferenceListHelpers.filteredSections(
                sections: sections,
                selection: selection
            )
        }
    }

    static func canOpen(_ item: ArticleReferenceItem) -> Bool {
        item.links.contains { validOpenURL(from: $0) != nil } || fallbackSearchURL(for: item) != nil
    }

    static func visibleSections(from sections: [ArticleReferenceSection]) -> [ArticleReferenceSection] {
        sections.compactMap { section in
            let items = section.items.filter { !isCitationNoise($0) }
            guard !items.isEmpty else { return nil }
            return ArticleReferenceSection(id: section.id, title: section.title, items: items)
        }
    }

    static func isCitationNoise(_ item: ArticleReferenceItem) -> Bool {
        isCitationNoise(text: item.text) || item.html.map(isCitationNoise(text:)) == true
    }

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
        guard let url = item.links.lazy.compactMap(validOpenURL(from:)).first ?? fallbackSearchURL(for: item) else {
            return
        }

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

    static func fallbackSearchURL(for item: ArticleReferenceItem) -> URL? {
        let query = fallbackSearchQuery(for: item)
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private static func fallbackSearchQuery(for item: ArticleReferenceItem) -> String {
        var text = item.text
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > 180 {
            text = String(text.prefix(180)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return text
    }

    private static func validOpenURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        guard !isReferenceUtilityURL(url) else {
            return nil
        }
        return url
    }

    private static func isReferenceUtilityURL(_ url: URL) -> Bool {
        guard url.host?.localizedCaseInsensitiveContains("wikipedia.org") == true else {
            return false
        }

        let path = url.path.removingPercentEncoding?.lowercased() ?? url.path.lowercased()
        return path.hasPrefix("/wiki/special:booksources") ||
            path == "/wiki/isbn_(identifier)" ||
            path == "/wiki/doi_(identifier)" ||
            path == "/wiki/pmid_(identifier)" ||
            path == "/wiki/s2cid_(identifier)"
    }

    private static func isCitationNoise(text rawText: String) -> Bool {
        let text = rawText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !text.isEmpty else { return false }

        if text.contains("cite.citation") ||
            text.contains("mw-parser-output") ||
            text.contains("cs1-") ||
            text.contains("background:url") ||
            text.contains("font-style:inherit") {
            return true
        }

        let cssDelimiterCount = text.filter { $0 == "{" || $0 == "}" }.count
        return cssDelimiterCount >= 4 && text.contains("citation")
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
