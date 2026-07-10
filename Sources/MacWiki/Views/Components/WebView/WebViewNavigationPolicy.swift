import Foundation

enum WebViewNavigationDisposition: Equatable {
    case allowInWebView
    case openExternally
    case cancel
}

enum WebViewNavigationPolicy {
    static func disposition(for url: URL, isUserInitiated: Bool) -> WebViewNavigationDisposition {
        guard let scheme = url.scheme?.lowercased() else { return .cancel }

        switch scheme {
        case "about", "data":
            return isUserInitiated ? .cancel : .allowInWebView
        case "http", "https":
            return isUserInitiated ? .openExternally : .allowInWebView
        case "mailto":
            return isUserInitiated ? .openExternally : .cancel
        default:
            return .cancel
        }
    }
}
