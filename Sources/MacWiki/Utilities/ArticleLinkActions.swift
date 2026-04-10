import Foundation

enum ArticleLinkActions {
    @discardableResult
    static func copyTitle(_ title: String) -> Bool {
        SystemBridge.copyText(title)
    }

    @discardableResult
    static func copyWikipediaLink(forTitle title: String) -> Bool {
        SystemBridge.copyText(wikipediaURLString(forTitle: title))
    }

    static func wikipediaURLString(forTitle title: String) -> String {
        WikipediaURLBuilder.articleURLString(forTitle: title)
    }
}
