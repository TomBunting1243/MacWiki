import Testing

@testable import MacWiki

struct WebViewMessageRouterTests {
    @Test func parsesStringLinkClickAsForegroundOpen() {
        let event = WebViewMessageRouter.route(name: "linkClicked", body: "https://en.wikipedia.org/wiki/Swift_(programming_language)")

        guard case .linkClicked(let payload)? = event else {
            Issue.record("Expected linkClicked payload")
            return
        }

        #expect(payload.urlString == "https://en.wikipedia.org/wiki/Swift_(programming_language)")
        #expect(payload.openInNewTab == false)
        #expect(payload.activateNewTab == true)
        #expect(payload.optionClick == false)
    }

    @Test func parsesCommandClickAsBackgroundTabOpen() {
        let body: [String: Any] = [
            "url": "https://en.wikipedia.org/wiki/Alan_Turing",
            "metaKey": true,
            "altKey": false
        ]

        let event = WebViewMessageRouter.route(name: "linkClicked", body: body)

        guard case .linkClicked(let payload)? = event else {
            Issue.record("Expected linkClicked payload")
            return
        }

        #expect(payload.openInNewTab == true)
        #expect(payload.activateNewTab == false)
        #expect(payload.optionClick == false)
    }

    @Test func parsesHighlightShortcutText() {
        let body: [String: Any] = ["text": "Important passage"]
        let event = WebViewMessageRouter.route(name: "highlightShortcut", body: body)

        guard case .highlightShortcut(let text)? = event else {
            Issue.record("Expected highlightShortcut payload")
            return
        }

        #expect(text == "Important passage")
    }
}
