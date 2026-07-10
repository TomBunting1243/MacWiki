import Foundation
import Testing
@testable import MacWiki

@Suite("Web view navigation security")
struct WebViewNavigationSecurityTests {
    @Test("Trusted document loads stay in the reader")
    func trustedDocumentLoadsStayInReader() throws {
        let wikipediaURL = try #require(URL(string: "https://en.wikipedia.org/wiki/Ada_Lovelace"))
        let aboutURL = try #require(URL(string: "about:blank"))
        let dataURL = try #require(URL(string: "data:text/html,hello"))

        #expect(WebViewNavigationPolicy.disposition(for: wikipediaURL, isUserInitiated: false) == .allowInWebView)
        #expect(WebViewNavigationPolicy.disposition(for: aboutURL, isUserInitiated: false) == .allowInWebView)
        #expect(WebViewNavigationPolicy.disposition(for: dataURL, isUserInitiated: false) == .allowInWebView)
    }

    @Test("User web and mail links leave the reader")
    func userExternalLinksLeaveReader() throws {
        let webURL = try #require(URL(string: "https://example.com/reference"))
        let mailURL = try #require(URL(string: "mailto:editor@example.com"))

        #expect(WebViewNavigationPolicy.disposition(for: webURL, isUserInitiated: true) == .openExternally)
        #expect(WebViewNavigationPolicy.disposition(for: mailURL, isUserInitiated: true) == .openExternally)
    }

    @Test("Executable, file, and custom schemes are denied")
    func unsafeSchemesAreDenied() throws {
        let unsafeURLs = try [
            "javascript:alert(document.cookie)",
            "file:///etc/passwd",
            "x-unknown:payload",
            "data:text/html,<script>alert(1)</script>"
        ].map { try #require(URL(string: $0)) }

        for url in unsafeURLs {
            #expect(WebViewNavigationPolicy.disposition(for: url, isUserInitiated: true) == .cancel)
        }
    }
}
