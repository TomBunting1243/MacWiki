import Foundation

private enum LinkHoverPreviewRoutingMetrics {
    static let dismissGraceDelay: TimeInterval = 0.38
}

extension WebView.Coordinator {
    func handleLinkHoverRequest(_ data: [String: Any]) {
        let state = (data["state"] as? String) ?? "show"
        if state == "hide" {
            isHoveringLinkPreviewSource = false
            dismissLinkHoverPreview(immediate: false)
            return
        }

        guard let urlString = data["url"] as? String,
              let url = URL(string: urlString) else {
            isHoveringLinkPreviewSource = false
            dismissLinkHoverPreview(immediate: false)
            return
        }

        let hoverTitle = hoverPreviewTitle(from: data, url: url)
        guard shouldPresentHoverPreview(for: url, previewTitle: hoverTitle) else {
            isHoveringLinkPreviewSource = false
            dismissLinkHoverPreview(immediate: false)
            return
        }

        isHoveringLinkPreviewSource = true

        let request = WebViewLinkHoverRequest(
            signature: linkHoverSignature(for: url),
            url: url,
            articleTitle: hoverTitle,
            point: WebViewContextMenuController.contextPoint(from: data)
        )
        presentLinkHoverPreview(for: request)
    }

    func hoverPreviewTitle(from data: [String: Any], url: URL) -> String? {
        if let raw = data["articleTitle"] as? String {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return articleTitle(from: url)
    }

    func shouldPresentHoverPreview(for url: URL, previewTitle: String?) -> Bool {
        guard let target = wikipediaLinkTarget(from: url) else { return false }
        let resolvedTitle = (previewTitle?.trimmingCharacters(in: .whitespacesAndNewlines))
            .flatMap { $0.isEmpty ? nil : $0 } ?? target.displayTitle
        guard !isMediaOnlyHoverPreviewTarget(title: target.displayTitle, url: url) else { return false }
        guard !isMediaOnlyHoverPreviewTarget(title: resolvedTitle, url: url) else { return false }
        return normalizedArticleKey(resolvedTitle) != normalizedArticleKey(articleTitle)
    }

    func isMediaOnlyHoverPreviewTarget(title: String, url: URL) -> Bool {
        let loweredTitle = normalizedArticleKey(title)
        if loweredTitle.hasPrefix("file:") ||
            loweredTitle.hasPrefix("image:") ||
            loweredTitle.hasPrefix("media:") {
            return true
        }

        let loweredExtension = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "apng", "avif", "bmp", "flac", "gif", "heic", "heif", "jpeg", "jpg",
            "mov", "mp3", "mp4", "ogg", "ogv", "png", "svg", "tif", "tiff",
            "wav", "webm", "webp"
        ].contains(loweredExtension)
    }

    func presentLinkHoverPreview(for request: WebViewLinkHoverRequest) {
        pendingLinkHoverHideWorkItem?.cancel()
        pendingLinkHoverHideWorkItem = nil

        if activeLinkHoverSignature == request.signature {
            publishLinkHoverPreview(request)
            return
        }

        activeLinkHoverSignature = request.signature
        publishLinkHoverPreview(request)
    }

    func linkHoverSignature(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    func syncLinkHoverPreviewOverlayState(isHovering: Bool, presentedSignature: String?) {
        let wasHovering = isHoveringLinkPreviewOverlay
        isHoveringLinkPreviewOverlay = isHovering

        if presentedSignature == nil {
            if activeLinkHoverSignature != nil && !isHoveringLinkPreviewSource {
                dismissLinkHoverPreview(immediate: true)
            }
            return
        }

        if isHovering {
            pendingLinkHoverHideWorkItem?.cancel()
            pendingLinkHoverHideWorkItem = nil
        } else if wasHovering && !isHoveringLinkPreviewSource {
            dismissLinkHoverPreview(immediate: false)
        }
    }

    func dismissLinkHoverPreview(immediate: Bool) {
        pendingLinkHoverHideWorkItem?.cancel()
        pendingLinkHoverHideWorkItem = nil

        let forceClose = { [weak self] in
            guard let self else { return }
            self.activeLinkHoverSignature = nil
            self.isHoveringLinkPreviewSource = false
            self.isHoveringLinkPreviewOverlay = false
            self.publishLinkHoverPreview(nil)
        }

        let closeAction = { [weak self] in
            guard let self else { return }
            guard !self.isHoveringLinkPreviewSource, !self.isHoveringLinkPreviewOverlay else { return }
            self.activeLinkHoverSignature = nil
            self.isHoveringLinkPreviewSource = false
            self.isHoveringLinkPreviewOverlay = false
            self.publishLinkHoverPreview(nil)
        }

        if immediate {
            forceClose()
            return
        }

        let workItem = DispatchWorkItem(block: closeAction)
        pendingLinkHoverHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + LinkHoverPreviewRoutingMetrics.dismissGraceDelay,
            execute: workItem
        )
    }

    func publishLinkHoverPreview(_ request: WebViewLinkHoverRequest?) {
        guard lastPublishedLinkHoverPreview != request else { return }
        lastPublishedLinkHoverPreview = request
        onLinkHoverPreviewChange?(request)
    }
}
