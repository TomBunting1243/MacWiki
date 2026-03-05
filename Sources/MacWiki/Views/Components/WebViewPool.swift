import AppKit
import Foundation
import WebKit

@MainActor
final class WebViewPool {
    struct Checkout {
        let webView: WKWebView
        let lastLoadedArticleTitle: String
        let lastLoadedHTMLSignature: UInt64
    }

    static let shared = WebViewPool()

    private struct Entry {
        let webView: WKWebView
        var lastLoadedArticleTitle: String
        var lastLoadedHTMLSignature: UInt64
    }

    private var entriesByTabID: [UUID: Entry] = [:]
    private var lruOrder: [UUID] = []
    private var retainedTabIDs: Set<UUID> = []
    private let maxRetainedWebViews = 4

    private init() {}

    func checkout(for tabID: UUID) -> Checkout? {
        guard let entry = entriesByTabID.removeValue(forKey: tabID) else { return nil }
        lruOrder.removeAll { $0 == tabID }
        return Checkout(
            webView: entry.webView,
            lastLoadedArticleTitle: entry.lastLoadedArticleTitle,
            lastLoadedHTMLSignature: entry.lastLoadedHTMLSignature
        )
    }

    func hasReusableWebView(for tabID: UUID) -> Bool {
        entriesByTabID[tabID] != nil
    }

    func store(
        _ webView: WKWebView,
        for tabID: UUID,
        lastLoadedArticleTitle: String,
        lastLoadedHTMLSignature: UInt64
    ) {
        guard !lastLoadedArticleTitle.isEmpty else { return }
        if !retainedTabIDs.isEmpty, !retainedTabIDs.contains(tabID) {
            release(webView)
            return
        }

        if let replaced = entriesByTabID.removeValue(forKey: tabID), replaced.webView !== webView {
            release(replaced.webView)
        }

        entriesByTabID[tabID] = Entry(
            webView: webView,
            lastLoadedArticleTitle: lastLoadedArticleTitle,
            lastLoadedHTMLSignature: lastLoadedHTMLSignature
        )
        lruOrder.removeAll { $0 == tabID }
        lruOrder.append(tabID)
        trimToBudget()
    }

    func retain(only tabIDs: Set<UUID>) {
        retainedTabIDs = tabIDs
        let toRemove = entriesByTabID.keys.filter { !tabIDs.contains($0) }
        for tabID in toRemove {
            guard let entry = entriesByTabID.removeValue(forKey: tabID) else { continue }
            lruOrder.removeAll { $0 == tabID }
            release(entry.webView)
        }
    }

    private func trimToBudget() {
        while entriesByTabID.count > maxRetainedWebViews {
            guard let evictID = lruOrder.first else { break }
            lruOrder.removeFirst()
            guard let entry = entriesByTabID.removeValue(forKey: evictID) else { continue }
            release(entry.webView)
        }
    }

    private func release(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
