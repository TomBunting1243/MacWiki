import Foundation
import WebKit

struct WebViewInspectorProjectionIdentity: Equatable, Sendable {
    let articleTitle: String
    let contentRevision: UInt64
    let generation: UInt64
}

extension WebView.Coordinator {
    func publishTableOfContents(from webView: WKWebView) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        guard let identity = inspectorProjectionIdentity(for: webView) else { return }
        guard let publicationID = inspectorPublisher.beginTableOfContentsPublish() else { return }
        webView.evaluateJavaScript("window.extractTableOfContents();") { [weak self, weak webView] result, error in
            guard let self else { return }
            defer { self.inspectorPublisher.endTableOfContentsPublish(publicationID) }
            guard let webView, self.isCurrentInspectorProjection(identity, on: webView) else { return }
            guard error == nil,
                  let rows = result as? [[String: Any]] else { return }
            let items: [ArticleTableOfContentsItem] = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let title = row["title"] as? String,
                      let level = row["level"] as? Int else {
                    return nil
                }
                return ArticleTableOfContentsItem(id: id, title: title, level: level)
            }
            self.inspectorProjection.tableOfContents = items
            self.inspectorProjection.hasTableOfContentsResult = true
            let shouldNotify = self.inspectorPublisher.recordTableOfContents(items)
            self.syncScrollTelemetryMode(on: webView)
            // extractTableOfContents normalizes heading IDs. Only resolve the
            // visible section after that normalization so the first selection
            // can never publish an obsolete pre-projection identifier.
            self.publishVisibleSection(from: webView, force: true)
            guard shouldNotify else { return }

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView,
                      self.isCurrentInspectorProjection(identity, on: webView) else { return }
                self.onTableOfContentsUpdate?(items)
            }
        }
    }

    func publishReferences(from webView: WKWebView) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        guard let identity = inspectorProjectionIdentity(for: webView) else { return }
        guard let publicationID = inspectorPublisher.beginReferencesPublish() else { return }
        webView.evaluateJavaScript("window.extractReferences ? window.extractReferences() : [];") { [weak self, weak webView] result, error in
            guard let self else { return }
            defer { self.inspectorPublisher.endReferencesPublish(publicationID) }
            guard let webView, self.isCurrentInspectorProjection(identity, on: webView) else { return }
            guard error == nil,
                  let rows = result as? [[String: Any]] else { return }
            let sections: [ArticleReferenceSection] = rows.compactMap { row in
                guard let title = row["title"] as? String else { return nil }
                let id = row["id"] as? String ?? title
                let itemsRaw = row["items"] as? [[String: Any]] ?? []
                let items: [ArticleReferenceItem] = itemsRaw.compactMap { item in
                    guard let itemId = item["id"] as? String,
                          let text = item["text"] as? String else { return nil }

                    let label = item["label"] as? String
                    let html = item["html"] as? String
                    let links = item["links"] as? [String] ?? []
                    let group = item["group"] as? String

                    return ArticleReferenceItem(
                        id: itemId,
                        label: label,
                        text: text,
                        html: html,
                        links: links,
                        group: group
                    )
                }
                guard !items.isEmpty else { return nil }
                return ArticleReferenceSection(id: id, title: title, items: items)
            }
            self.inspectorProjection.references = sections
            self.inspectorProjection.hasReferencesResult = true
            guard self.inspectorPublisher.recordReferences(sections) else { return }

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView,
                      self.isCurrentInspectorProjection(identity, on: webView) else { return }
                self.onReferencesUpdate?(sections)
            }
        }
    }

    func publishVisibleSection(from webView: WKWebView, force: Bool = false) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        guard let identity = inspectorProjectionIdentity(for: webView) else { return }
        let querySequence = inspectorPublisher.beginVisibleSectionQuery()
        webView.evaluateJavaScript("window.currentVisibleSectionId ? window.currentVisibleSectionId() : null;") { [weak self, weak webView] result, _ in
            guard let self, let webView,
                  self.isCurrentInspectorProjection(identity, on: webView) else { return }
            let sectionId = result as? String
            guard self.inspectorPublisher.shouldPublishVisibleSection(
                sectionId,
                force: force,
                ifUnchangedSince: querySequence
            ) else { return }
            self.inspectorProjection.visibleSectionID = sectionId
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView,
                      self.isCurrentInspectorProjection(identity, on: webView) else { return }
                self.onVisibleSectionChange?(sectionId)
            }
        }
    }

    /// Restore a prepared projection with the pooled Reader surface. A reused
    /// document should not reserialize its references or rebuild heading IDs;
    /// only genuinely missing projection pieces are requested from WebKit.
    func restoreInspectorProjection(
        _ projection: WebViewPool.InspectorProjection,
        on webView: WKWebView
    ) {
        guard let identity = inspectorProjectionIdentity(for: webView) else { return }

        inspectorPublisher.resetForContentReload()
        inspectorProjection = projection

        if projection.hasTableOfContentsResult {
            _ = inspectorPublisher.recordTableOfContents(projection.tableOfContents)
        }
        if projection.hasReferencesResult {
            _ = inspectorPublisher.recordReferences(projection.references)
        }
        _ = inspectorPublisher.shouldPublishVisibleSection(
            projection.visibleSectionID,
            force: true
        )
        syncScrollTelemetryMode(on: webView, force: true)

        // Reader/AppState callbacks can mutate SwiftUI state. Defer them one
        // main turn so attaching an NSView never publishes into the graph that
        // is currently constructing that same representable.
        DispatchQueue.main.async { [weak self, weak webView] in
            guard let self, let webView,
                  self.isCurrentInspectorProjection(identity, on: webView) else { return }
            let currentProjection = self.inspectorProjection
            self.onTableOfContentsUpdate?(
                currentProjection.hasTableOfContentsResult ? currentProjection.tableOfContents : []
            )
            self.onReferencesUpdate?(
                currentProjection.hasReferencesResult ? currentProjection.references : []
            )
            self.onVisibleSectionChange?(currentProjection.visibleSectionID)

            if !currentProjection.hasTableOfContentsResult {
                self.publishTableOfContents(from: webView)
            }
            if !currentProjection.hasReferencesResult {
                self.scheduleForCurrentWebView(after: 0.18, webView: webView) { [weak self, weak webView] in
                    guard let self, let webView,
                          self.isCurrentInspectorProjection(identity, on: webView) else { return }
                    self.publishReferences(from: webView)
                }
            }
        }
    }

    func inspectorProjectionIdentity(
        for webView: WKWebView
    ) -> WebViewInspectorProjectionIdentity? {
        guard self.webView === webView,
              !articleTitle.isEmpty,
              lastLoadedArticleTitle == articleTitle,
              lastLoadedHTMLSignature == currentContentRevision else {
            return nil
        }
        return WebViewInspectorProjectionIdentity(
            articleTitle: articleTitle,
            contentRevision: currentContentRevision,
            generation: inspectorProjectionGeneration
        )
    }

    func isCurrentInspectorProjection(
        _ identity: WebViewInspectorProjectionIdentity,
        on webView: WKWebView
    ) -> Bool {
        inspectorProjectionIdentity(for: webView) == identity
    }
}
