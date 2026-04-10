import Foundation

/// Data passed from JavaScript when text is selected
struct TextSelectionData: Equatable {
    let text: String
    let elementPath: String
    let startOffset: Int
    let length: Int
    let contextBefore: String
    let contextAfter: String
    let sectionTitle: String?
    let rect: CGRect  // Position for toolbar
}

/// Data for link action requests coming from WebView right-click events.
struct WebViewLinkContextRequest: Equatable {
    let url: URL
    let articleTitle: String?
    let point: CGPoint
}

/// Data for highlight action requests coming from WebView right-click events.
struct WebViewHighlightContextRequest: Equatable {
    let id: UUID
    let point: CGPoint
}

/// Data for selected text right-click actions coming from WebView.
struct WebViewSelectionContextRequest: Equatable {
    let selection: TextSelectionData
    let point: CGPoint
}

/// Data for link hover preview requests coming from WebView hover events.
struct WebViewLinkHoverRequest: Equatable, Sendable {
    let signature: String
    let url: URL
    let articleTitle: String?
    let point: CGPoint
}
