import Foundation
import WebKit

extension WebView.Coordinator {
    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let name = message.name
        let body = message.body

        if Thread.isMainThread {
            handleScriptMessage(name: name, body: body)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.handleScriptMessage(name: name, body: body)
            }
        }
    }

    func handleScriptMessage(name: String, body: Any) {
        guard let routedMessage = WebViewMessageRouter.route(name: name, body: body) else {
            return
        }

        switch routedMessage {
        case .linkClicked(let payload):
            handleLinkClick(
                payload.urlString,
                openInNewTab: payload.openInNewTab,
                activateNewTab: payload.activateNewTab,
                optionClick: payload.optionClick
            )

        case .linkRightClicked(let data):
            handleLinkContextRequest(data)

        case .linkHoverChanged(let data):
            handleLinkHoverRequest(data)

        case .textSelected(let data):
            handleTextSelection(data)

        case .selectionCleared:
            onSelectionCleared?()

        case .textSelectionContextRequested(let data):
            handleSelectionContextRequest(data)

        case .scrollChanged(let data):
            handleScrollChanged(data)

        case .scrollPerfSnapshot(let data):
            handleScrollPerfSnapshot(data)

        case .scrollRestoreReady(let data):
            handleScrollRestoreReady(data)

        case .highlightShortcut(let text):
            appState?.pendingHighlightText = text

        case .highlightClicked(let idString):
            appState?.selectedHighlightId = idString
            appState?.inspectorMode = .notes
            appState?.inspectorVisible = true

        case .highlightResult(let data):
            applyHighlightRehydrateResult(data)

        case .highlightRightClicked(let data):
            handleHighlightContextRequest(data)

        case .referenceClicked(let referenceId):
            appState?.selectedReferenceId = normalizedReferenceIdentifier(referenceId)
            appState?.inspectorMode = .references
            appState?.inspectorVisible = true
        }
    }

    func applyHighlightRehydrateResult(_ data: [String: Any]) {
        guard let failedIds = data["failedIds"] as? [String] else { return }
        let failedSet = Set(failedIds.compactMap { UUID(uuidString: $0) })
        var didChange = false

        for highlight in highlights {
            let shouldBeStale = failedSet.contains(highlight.id)
            if highlight.isStale != shouldBeStale {
                highlight.isStale = shouldBeStale
                didChange = true
            }
        }

        if didChange {
            try? modelContext?.save()
        }
    }

    func completePendingHighlightRehydrate(
        _ pending: AppState.HighlightRehydrateRequest,
        success: Bool,
        timestamp: Date = Date()
    ) {
        appState?.isHighlightRehydrateInProgress = false
        appState?.pendingHighlightRehydrate = nil
        appState?.lastHighlightRehydrateResult = AppState.HighlightRehydrateResult(
            id: pending.id,
            success: success,
            timestamp: timestamp
        )

        guard success else { return }
        guard let target = highlights.first(where: { $0.id == pending.id }) else { return }
        target.isStale = false
        target.updatedAt = timestamp
        try? modelContext?.save()
    }

    func handleTextSelection(_ data: [String: Any]) {
        guard let selectionData = parseTextSelectionData(from: data) else { return }
        onTextSelected?(selectionData)
    }

    func handleSelectionContextRequest(_ data: [String: Any]) {
        guard let selectionData = parseTextSelectionData(from: data) else { return }
        let request = WebViewSelectionContextRequest(
            selection: selectionData,
            point: WebViewContextMenuController.contextPoint(from: data)
        )
        presentNativeSelectionContextMenu(for: request)
    }

    func parseTextSelectionData(from data: [String: Any]) -> TextSelectionData? {
        guard let text = data["text"] as? String,
              let elementPath = data["elementPath"] as? String,
              let startOffset = data["startOffset"] as? Int,
              let length = data["length"] as? Int,
              let rectData = data["rect"] as? [String: Any],
              let x = WebViewContextMenuController.numericValue(from: rectData["x"]),
              let y = WebViewContextMenuController.numericValue(from: rectData["y"]),
              let width = WebViewContextMenuController.numericValue(from: rectData["width"]),
              let height = WebViewContextMenuController.numericValue(from: rectData["height"])
        else {
            return nil
        }

        return TextSelectionData(
            text: text,
            elementPath: elementPath,
            startOffset: startOffset,
            length: length,
            contextBefore: data["contextBefore"] as? String ?? "",
            contextAfter: data["contextAfter"] as? String ?? "",
            sectionTitle: data["sectionTitle"] as? String,
            rect: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    func normalizedReferenceIdentifier(_ rawIdentifier: String) -> String {
        rawIdentifier.removingPercentEncoding ?? rawIdentifier
    }

    func handleLinkClick(
        _ urlString: String,
        openInNewTab: Bool = false,
        activateNewTab: Bool = true,
        optionClick: Bool = false
    ) {
        dismissLinkHoverPreview(immediate: true)
        guard let url = URL(string: urlString) else { return }
        guard shouldHandleLink(url: url, newTab: openInNewTab, optionSave: optionClick) else { return }

        if let target = wikipediaLinkTarget(from: url) {
            let normalizedCurrentTitle = normalizedArticleKey(articleTitle)
            let normalizedTargetTitle = normalizedArticleKey(target.displayTitle)
            let fragment = url.fragment?.trimmingCharacters(in: .whitespacesAndNewlines)
            if !openInNewTab,
               normalizedCurrentTitle == normalizedTargetTitle,
               let fragment,
               !fragment.isEmpty {
                scrollToAnchor(fragment)
                return
            }

            if optionClick {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let article = Article(id: target.id, title: target.displayTitle)
                    self.appState?.presentOptionClickSavePrompt(for: article)
                }
                return
            }

            if openInNewTab {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    let article = Article(id: target.id, title: target.displayTitle)
                    self.appState?.openArticleInNewTab(article, activate: activateNewTab)
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.onLinkTapped?(target.displayTitle)
                }
            }
            return
        }

        if url.scheme == "http" || url.scheme == "https" {
            DispatchQueue.main.async {
                _ = SystemBridge.openURLExternally(url)
            }
        }
    }

    func shouldHandleLink(url: URL, newTab: Bool, optionSave: Bool = false) -> Bool {
        let now = Date().timeIntervalSinceReferenceDate
        if (now - lastHandledAnyLinkTimestamp) < 0.07 {
            return false
        }

        let signature: String
        if let target = wikipediaLinkTarget(from: url) {
            signature = "wiki:\(normalizedArticleKey(target.displayTitle))|\(newTab ? "1" : "0")|\(optionSave ? "1" : "0")"
        } else {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            signature = "\(components?.string ?? url.absoluteString)|\(newTab ? "1" : "0")|\(optionSave ? "1" : "0")"
        }

        let isDuplicate = signature == lastHandledLinkSignature && (now - lastHandledLinkTimestamp) < 0.9
        if isDuplicate {
            return false
        }
        lastHandledLinkSignature = signature
        lastHandledLinkTimestamp = now
        lastHandledAnyLinkTimestamp = now
        return true
    }

    struct WikipediaLinkTarget {
        let id: String
        let displayTitle: String
    }

    func wikipediaLinkTarget(from url: URL) -> WikipediaLinkTarget? {
        if let rawPathTitle = wikipediaRawTitle(fromPath: url.path) {
            return wikipediaLinkTarget(rawTitle: rawPathTitle)
        }

        guard wikipediaIndexPath(url.path),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              shouldTreatIndexRouteAsArticle(using: components),
              let queryTitle = queryItemValue(named: "title", in: components) else {
            return nil
        }
        return wikipediaLinkTarget(rawTitle: queryTitle)
    }

    func wikipediaRawTitle(fromPath path: String) -> String? {
        guard let range = path.range(of: "/wiki/", options: .backwards) else {
            return nil
        }
        let rawTitle = String(path[range.upperBound...])
        return rawTitle.isEmpty ? nil : rawTitle
    }

    func wikipediaIndexPath(_ path: String) -> Bool {
        let lowered = path.lowercased()
        return lowered == "/w/index.php" ||
            lowered.hasSuffix("/w/index.php") ||
            lowered == "/wiki/index.php" ||
            lowered.hasSuffix("/wiki/index.php")
    }

    func shouldTreatIndexRouteAsArticle(using components: URLComponents) -> Bool {
        let action = queryItemValue(named: "action", in: components)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard let action, !action.isEmpty else { return true }
        if action == "view" { return true }
        if action == "edit" {
            let redlink = queryItemValue(named: "redlink", in: components)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if redlink == "1" || redlink == "true" {
                return true
            }
        }
        return false
    }

    func queryItemValue(named name: String, in components: URLComponents) -> String? {
        components.queryItems?
            .first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }?
            .value
    }

    func wikipediaLinkTarget(rawTitle: String) -> WikipediaLinkTarget? {
        var trimmed = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let fragmentIndex = trimmed.firstIndex(of: "#") {
            trimmed = String(trimmed[..<fragmentIndex])
        }
        guard !trimmed.isEmpty else { return nil }

        let decoded = trimmed.removingPercentEncoding ?? trimmed
        let plusDecoded = decoded.replacingOccurrences(of: "+", with: " ")
        let articleID = plusDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
        let displayTitle = plusDecoded
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")

        guard !articleID.isEmpty, !displayTitle.isEmpty else { return nil }
        return WikipediaLinkTarget(id: articleID, displayTitle: displayTitle)
    }

    func normalizedArticleKey(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
    }

    func scrollToAnchor(_ fragment: String) {
        guard let webView else { return }
        let escapedFragment = fragment
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
        let script = "window.scrollToAnchor && window.scrollToAnchor('\(escapedFragment)');"
        webView.evaluateJavaScript(script)
    }

    func handleLinkContextRequest(_ data: [String: Any]) {
        dismissLinkHoverPreview(immediate: true)
        guard let urlString = data["url"] as? String else { return }
        guard let url = URL(string: urlString) else { return }
        let request = WebViewLinkContextRequest(
            url: url,
            articleTitle: articleTitle(from: url),
            point: WebViewContextMenuController.contextPoint(from: data)
        )
        presentNativeLinkContextMenu(for: request)
    }

    func handleHighlightContextRequest(_ data: [String: Any]) {
        guard let idString = data["id"] as? String else { return }
        guard let uuid = UUID(uuidString: idString) else { return }
        let request = WebViewHighlightContextRequest(
            id: uuid,
            point: WebViewContextMenuController.contextPoint(from: data)
        )
        presentNativeHighlightContextMenu(for: request)
    }

    func articleTitle(from url: URL) -> String? {
        wikipediaLinkTarget(from: url)?.displayTitle
    }
}
