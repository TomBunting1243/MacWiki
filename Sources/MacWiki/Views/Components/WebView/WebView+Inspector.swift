import Foundation
import WebKit

extension WebView.Coordinator {
    func publishTableOfContents(from webView: WKWebView) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        guard inspectorPublisher.beginTableOfContentsPublish() else { return }
        webView.evaluateJavaScript("window.extractTableOfContents();") { [weak self] result, error in
            guard let self else { return }
            defer { self.inspectorPublisher.endTableOfContentsPublish() }
            if error != nil {
                return
            }

            guard let rows = result as? [[String: Any]] else {
                guard self.inspectorPublisher.recordTableOfContents([]) else { return }
                DispatchQueue.main.async {
                    self.onTableOfContentsUpdate?([])
                }
                return
            }

            let items: [ArticleTableOfContentsItem] = rows.compactMap { row in
                guard let id = row["id"] as? String,
                      let title = row["title"] as? String,
                      let level = row["level"] as? Int else {
                    return nil
                }
                return ArticleTableOfContentsItem(id: id, title: title, level: level)
            }
            guard self.inspectorPublisher.recordTableOfContents(items) else { return }

            DispatchQueue.main.async {
                self.onTableOfContentsUpdate?(items)
            }
        }
    }

    func publishReferences(from webView: WKWebView) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        guard inspectorPublisher.beginReferencesPublish() else { return }
        webView.evaluateJavaScript("window.extractReferences ? window.extractReferences() : [];") { [weak self] result, error in
            guard let self else { return }
            defer { self.inspectorPublisher.endReferencesPublish() }
            if error != nil {
                return
            }

            guard let rows = result as? [[String: Any]] else {
                guard self.inspectorPublisher.recordReferences([]) else { return }
                DispatchQueue.main.async {
                    self.onReferencesUpdate?([])
                }
                return
            }

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
            guard self.inspectorPublisher.recordReferences(sections) else { return }

            DispatchQueue.main.async {
                self.onReferencesUpdate?(sections)
            }
        }
    }

    func publishVisibleSection(from webView: WKWebView, force: Bool = false) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }
        webView.evaluateJavaScript("window.currentVisibleSectionId ? window.currentVisibleSectionId() : null;") { [weak self] result, _ in
            guard let self else { return }
            let sectionId = result as? String
            guard self.inspectorPublisher.shouldPublishVisibleSection(sectionId, force: force) else { return }
            DispatchQueue.main.async {
                self.onVisibleSectionChange?(sectionId)
            }
        }
    }

    func refreshDeferredInspectorContentIfNeeded(on webView: WKWebView) {
        guard !isContentLoadInFlight, canRunDocumentJavaScript(on: webView) else { return }

        if isSectionTrackingRequested, inspectorPublisher.lastTOCPublishedForTitle != articleTitle {
            inspectorPublisher.lastTOCPublishedForTitle = articleTitle
            inspectorPublisher.clearPublishedTableOfContentsFingerprint()
            publishTableOfContents(from: webView)
            publishVisibleSection(from: webView, force: true)
        }

        if isReferencesRequested, inspectorPublisher.lastReferencesPublishedForTitle != articleTitle {
            inspectorPublisher.lastReferencesPublishedForTitle = articleTitle
            inspectorPublisher.clearPublishedReferencesFingerprint()
            publishReferences(from: webView)
        }
    }
}
