import Foundation

enum WikipediaURLBuilder {
    private static let articleBase = "https://en.wikipedia.org/wiki/"
    private static let pathComponentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return allowed
    }()

    private static func normalizedSlug(forTitle title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    static func articleURL(forTitle title: String) -> URL? {
        let slug = normalizedSlug(forTitle: title)
        guard !slug.isEmpty else { return nil }
        guard let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: pathComponentAllowed) else {
            return nil
        }
        return URL(string: articleBase + encodedSlug)
    }

    static func articleURLString(forTitle title: String) -> String {
        articleURL(forTitle: title)?.absoluteString ?? (articleBase + normalizedSlug(forTitle: title))
    }
}
