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
    private var retainedTabIDsByOwner: [UUID: Set<UUID>] = [:]
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
        if !canStoreWebView(for: tabID) {
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

    func retain(only tabIDs: Set<UUID>, for ownerID: UUID) {
        retainedTabIDsByOwner[ownerID] = tabIDs
        releaseEntriesOutsideRetainedUnion()
    }

    func releaseOwner(_ ownerID: UUID) {
        retainedTabIDsByOwner.removeValue(forKey: ownerID)
        releaseEntriesOutsideRetainedUnion()
    }

#if DEBUG
    func retainedTabIDsForTesting() -> Set<UUID> {
        retainedTabIDsSnapshot
    }

    func canStoreWebViewForTesting(for tabID: UUID) -> Bool {
        canStoreWebView(for: tabID)
    }

    func resetForTesting() {
        for entry in entriesByTabID.values {
            release(entry.webView)
        }
        entriesByTabID.removeAll()
        lruOrder.removeAll()
        retainedTabIDsByOwner.removeAll()
    }
#endif

    private var retainedTabIDsSnapshot: Set<UUID> {
        retainedTabIDsByOwner.values.reduce(into: Set<UUID>()) { union, tabIDs in
            union.formUnion(tabIDs)
        }
    }

    private func canStoreWebView(for tabID: UUID) -> Bool {
        retainedTabIDsByOwner.isEmpty || retainedTabIDsSnapshot.contains(tabID)
    }

    private func releaseEntriesOutsideRetainedUnion() {
        let retainedTabIDs = retainedTabIDsSnapshot
        let toRemove = entriesByTabID.keys.filter { !retainedTabIDs.contains($0) }
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
