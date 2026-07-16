import SwiftUI
import AppKit
import WebKit
import SwiftData

enum ReaderDocumentRevision {
    /// Deterministic full-document digest computed when article state is
    /// published, outside scroll-driven `updateNSView` calls.
    static func digest(for html: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in html.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return hash
    }
}

struct WebViewTableOfContentsScrollRequest: Equatable {
    let sequence: UInt64
    let sectionID: String
    let articleTitle: String
    let contentRevision: UInt64
}

enum WebViewTableOfContentsScrollCompletion: Equatable {
    case ignored
    case succeeded(sectionID: String)
    case failed(sectionID: String)
}

/// Orders asynchronous TOC scroll completions so a cancelled scroll, rapid
/// second click, or article switch cannot publish stale inspector selection.
final class WebViewTableOfContentsScrollRequestTracker {
    private var nextSequence: UInt64 = 0
    private(set) var activeRequest: WebViewTableOfContentsScrollRequest?

    func begin(
        sectionID: String,
        articleTitle: String,
        contentRevision: UInt64
    ) -> WebViewTableOfContentsScrollRequest? {
        if let activeRequest,
           activeRequest.sectionID == sectionID,
           activeRequest.articleTitle == articleTitle,
           activeRequest.contentRevision == contentRevision {
            return nil
        }

        nextSequence &+= 1
        let request = WebViewTableOfContentsScrollRequest(
            sequence: nextSequence,
            sectionID: sectionID,
            articleTitle: articleTitle,
            contentRevision: contentRevision
        )
        activeRequest = request
        return request
    }

    func finish(
        _ request: WebViewTableOfContentsScrollRequest,
        didReachTarget: Bool,
        pendingSectionID: String?,
        currentArticleTitle: String,
        currentContentRevision: UInt64
    ) -> WebViewTableOfContentsScrollCompletion {
        guard activeRequest == request else { return .ignored }
        activeRequest = nil

        guard pendingSectionID == request.sectionID,
              currentArticleTitle == request.articleTitle,
              currentContentRevision == request.contentRevision else {
            return .ignored
        }

        return didReachTarget
            ? .succeeded(sectionID: request.sectionID)
            : .failed(sectionID: request.sectionID)
    }

    func invalidate() {
        nextSequence &+= 1
        activeRequest = nil
    }
}

private enum ReaderChromeDefaults {
    static let defaultTopInset: CGFloat = 56
}

/// SwiftUI wrapper for WKWebView to display Wikipedia article content
struct WebView: NSViewRepresentable {
    @Environment(\.modelContext) private var modelContext
    /// Stable tab identity used to retain and restore live WKWebView instances.
    let tabID: UUID

    /// HTML content to display
    let htmlContent: String

    /// Full-document revision computed at the article load boundary.
    let contentRevision: UInt64

    /// Article title for highlight association
    let articleTitle: String

    /// Base URL for resolving relative links (must end in /wiki/ for ./ links to work)
    var baseURL: URL? = URL(string: "https://en.wikipedia.org/wiki/")

    /// Callback when a Wikipedia link is tapped
    var onLinkTapped: ((String) -> Void)?

    /// Callback when a Wikipedia article should open in a separate app window.
    var onOpenArticleInNewWindow: ((Article) -> Void)?

    /// Callback when text is selected (for showing highlight toolbar)
    var onTextSelected: ((TextSelectionData) -> Void)?

    /// Callback when selection is cleared
    var onSelectionCleared: (() -> Void)?

    /// Highlights to render in the article
    var highlights: [Highlight] = []

    /// Current scroll position (for state preservation)
    @Binding var scrollPosition: CGFloat

    /// Callback when scroll progress updates (0.0 - 1.0)
    var onScrollProgress: ((Double) -> Void)?

    /// Persisted article progress (0.0 - 1.0) used as a restore fallback when absolute scroll Y is unavailable.
    var fallbackScrollProgress: Double?

    /// Reader typography/layout settings applied via CSS variables
    var readerAppearance: ReaderAppearance = .default

    /// Native accessibility preference mirrored into the reader document root.
    var reduceTransparency: Bool = false

    /// Adds a shape cue to color-coded reader highlights.
    var differentiateWithoutColor: Bool = false

    /// Top inset reserved for window + tab chrome so article headings remain visible.
    var readerTopInset: CGFloat = ReaderChromeDefaults.defaultTopInset

    /// When true, prefer immediate reveal for warm cache opens to reduce visible pop/flicker.
    var preferImmediateReveal: Bool = false

    /// Callback when article table of contents is extracted from headings
    var onTableOfContentsUpdate: (([ArticleTableOfContentsItem]) -> Void)?

    /// Callback when article references are extracted from the page.
    var onReferencesUpdate: (([ArticleReferenceSection]) -> Void)?

    /// Callback when currently visible section changes while scrolling
    var onVisibleSectionChange: ((String?) -> Void)?

    /// Callback when the web content is fully revealed to the user.
    var onContentReveal: (() -> Void)?

    /// Callback when WebKit cannot render the current article document.
    var onContentLoadFailure: ((Error) -> Void)?

    /// Callback when the reader should show or hide a floating link-hover preview.
    var onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?

    /// Whether the SwiftUI hover-preview overlay is currently hovered.
    var linkHoverPreviewOverlayHovering: Bool = false

    /// Signature of the hover-preview overlay currently presented by SwiftUI.
    var activeLinkHoverPreviewSignature: String?

    /// Modifier that bypasses the standard hover delay for link previews.
    var linkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier = .default

    /// Enables native context-menu driven text highlighting interactions.
    var nativeHighlightingMenuEnabled: Bool = false

    /// Optional open-path timer for phase instrumentation.
    var openTimer: Binding<ArticleOpenTimer>?

    // Dependencies for Context Menu
    var appState: AppState?

    var findOnPageRequestID: UUID?

    private static let scriptMessageHandlerNames = [
        "linkClicked",
        "linkRightClicked",
        "linkHoverChanged",
        "textSelected",
        "selectionCleared",
        "textSelectionContextRequested",
        "highlightShortcut",
        "highlightClicked",
        "highlightResult",
        "highlightRightClicked",
        "referenceClicked",
        "scrollChanged",
        "scrollPerfSnapshot",
        "scrollRestoreReady"
    ]

    /// Encodes a Swift string as a safe JavaScript string literal.
    static func javaScriptStringLiteral(_ value: String) -> String {
        WebViewJavaScript.stringLiteral(value)
    }


    func makeNSView(context: Context) -> WKWebView {
        if let checkout = WebViewPool.shared.checkout(for: tabID) {
            let webView = checkout.webView
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            webView.allowsLinkPreview = false
            context.coordinator.bootstrapAppearance = readerAppearance
            context.coordinator.lastLoadedArticleTitle = checkout.lastLoadedArticleTitle
            context.coordinator.lastLoadedHTMLSignature = checkout.lastLoadedHTMLSignature
            Self.unregisterScriptMessageHandlers(from: webView)
            Self.registerScriptMessageHandlers(on: webView, coordinator: context.coordinator)
            context.coordinator.attachReusedWebView(
                webView,
                inspectorProjection: checkout.inspectorProjection
            )
            return webView
        }

        let configuration = WKWebViewConfiguration()

        // Enable content blocking for cleaner display
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsLinkPreview = false
        webView.setValue(false, forKey: "drawsBackground")
        if #available(macOS 11.0, *) {
            webView.underPageBackgroundColor = .clear
        }
        webView.wantsLayer = true
        webView.layer?.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)

        // Enable Web Inspector for debugging (right-click → Inspect Element)
        #if DEBUG
        webView.isInspectable = true
        #endif

        // CRITICAL: Ensure resizing works in SwiftUI
        webView.autoresizingMask = [.width, .height]
        webView.alphaValue = 0

        let appearanceBootstrapScript = WKUserScript(
            source: Self.makeReaderAppearanceBootstrapScript(from: readerAppearance.webPayload),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(appearanceBootstrapScript)
        let nativeHighlightMenuBootstrapScript = WKUserScript(
            source: "window._macwikiNativeHighlightingMenuEnabled = \(nativeHighlightingMenuEnabled ? "true" : "false");",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(nativeHighlightMenuBootstrapScript)
        let linkPreviewImmediateModifierBootstrapScript = WKUserScript(
            source: "window._macwikiLinkPreviewImmediateModifier = '\(linkPreviewImmediateModifier.javaScriptValue)';",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(linkPreviewImmediateModifierBootstrapScript)
        context.coordinator.bootstrapAppearance = readerAppearance

        let readerDocumentScript = WKUserScript(
            source: ReaderDocumentStyle.makeInjectionScript(
                minimumReadableColumnWidth: ReaderAppearance.minimumReadableColumnWidth,
                readerTopInset: readerTopInset,
                reduceTransparency: reduceTransparency,
                differentiateWithoutColor: differentiateWithoutColor
            ),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(readerDocumentScript)

        let webViewScript = WKUserScript(
            source: WebViewResources.scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(webViewScript)


        // Register handlers
        Self.registerScriptMessageHandlers(on: webView, coordinator: context.coordinator)
        context.coordinator.attachNewWebView(webView)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Update coordinator bindings and callbacks
        context.coordinator.scrollPosition = $scrollPosition
        context.coordinator.onScrollProgress = onScrollProgress
        context.coordinator.fallbackScrollProgress = fallbackScrollProgress
        context.coordinator.appState = appState
        context.coordinator.modelContext = modelContext
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onSelectionCleared = onSelectionCleared
        context.coordinator.highlights = highlights
        context.coordinator.articleTitle = articleTitle
        context.coordinator.currentContentRevision = contentRevision
        context.coordinator.readerAppearance = readerAppearance
        context.coordinator.reduceTransparency = reduceTransparency
        context.coordinator.differentiateWithoutColor = differentiateWithoutColor
        context.coordinator.readerTopInset = readerTopInset
        context.coordinator.preferImmediateReveal = preferImmediateReveal
        context.coordinator.onTableOfContentsUpdate = onTableOfContentsUpdate
        context.coordinator.onReferencesUpdate = onReferencesUpdate
        context.coordinator.onVisibleSectionChange = onVisibleSectionChange
        context.coordinator.onContentReveal = onContentReveal
        context.coordinator.onContentLoadFailure = onContentLoadFailure
        context.coordinator.onLinkHoverPreviewChange = onLinkHoverPreviewChange
        context.coordinator.linkPreviewImmediateModifier = linkPreviewImmediateModifier
        context.coordinator.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        context.coordinator.openTimer = openTimer
        context.coordinator.syncLinkHoverPreviewOverlayState(
            isHovering: linkHoverPreviewOverlayHovering,
            presentedSignature: activeLinkHoverPreviewSignature
        )
        context.coordinator.syncLinkPreviewImmediateModifier(on: webView)
        context.coordinator.syncNativeHighlightMenuMode(on: webView)
        context.coordinator.syncReaderAccessibilityStyle(on: webView)

        // Process all pending actions (don't early-return so multiple can be handled)
        var didProcessPendingAction = false

        // Apply a color selected from the native highlight popover to the current WebView selection.
        if let pending = appState?.pendingImmediateHighlight,
           !context.coordinator.isContentLoadInFlight,
           context.coordinator.canRunDocumentJavaScript(on: webView) {
            let script = "window.highlightCurrentSelection('\(pending.id.uuidString)', '\(pending.cssColor)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingImmediateHighlight = nil
            }
            context.coordinator.lastAppliedHighlightIds.insert(pending.id)
            didProcessPendingAction = true
        }

        // Apply pending highlight color change in WebView
        if let pending = appState?.pendingHighlightColorChange,
           !context.coordinator.isContentLoadInFlight,
           context.coordinator.canRunDocumentJavaScript(on: webView) {
            let script = "window.updateHighlightColor('\(pending.id.uuidString)', '\(pending.cssColor)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingHighlightColorChange = nil
            }
            didProcessPendingAction = true
        }

        // Scroll to a specific highlight
        if let pending = appState?.pendingHighlightScroll,
           !context.coordinator.isContentLoadInFlight,
           context.coordinator.canRunDocumentJavaScript(on: webView) {
            let script = "window.scrollToHighlight('\(pending.uuidString)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingHighlightScroll = nil
            }
            didProcessPendingAction = true
        }

        // Scroll to a specific heading from Table of Contents
        if let sectionId = appState?.pendingTableOfContentsScrollTarget,
           !context.coordinator.isContentLoadInFlight,
           context.coordinator.canRunDocumentJavaScript(on: webView),
           context.coordinator.lastLoadedArticleTitle == articleTitle,
           context.coordinator.lastLoadedHTMLSignature == contentRevision,
           let request = context.coordinator.tableOfContentsScrollRequestTracker.begin(
               sectionID: sectionId,
               articleTitle: articleTitle,
               contentRevision: contentRevision
           ) {
            let coordinator = context.coordinator
            let appState = appState
            Task { @MainActor [weak webView, weak coordinator] in
                guard let webView, let coordinator else { return }
                guard coordinator.tableOfContentsScrollRequestTracker.activeRequest == request else {
                    return
                }
                guard appState?.pendingTableOfContentsScrollTarget == request.sectionID,
                      appState?.currentArticle?.title == request.articleTitle,
                      coordinator.articleTitle == request.articleTitle,
                      coordinator.currentContentRevision == request.contentRevision,
                      coordinator.lastLoadedArticleTitle == request.articleTitle,
                      coordinator.lastLoadedHTMLSignature == request.contentRevision else {
                    coordinator.tableOfContentsScrollRequestTracker.invalidate()
                    return
                }
                let result = try? await webView.callAsyncJavaScript(
                    "return await window.scrollToSection(sectionID);",
                    arguments: ["sectionID": sectionId],
                    in: nil,
                    contentWorld: .page
                )
                let completion = coordinator.tableOfContentsScrollRequestTracker.finish(
                    request,
                    didReachTarget: result as? Bool == true,
                    pendingSectionID: appState?.pendingTableOfContentsScrollTarget,
                    currentArticleTitle: appState?.currentArticle?.title ?? "",
                    currentContentRevision: coordinator.currentContentRevision
                )
                switch completion {
                case .ignored:
                    break
                case .succeeded(let completedSectionID):
                    appState?.currentVisibleTableOfContentsSectionId = completedSectionID
                    appState?.pendingTableOfContentsScrollTarget = nil
                case .failed:
                    // The request was consumed, but a missing/cancelled target
                    // must not become the inspector's visible selection.
                    appState?.pendingTableOfContentsScrollTarget = nil
                }
            }
            didProcessPendingAction = true
        }

        // In-page find (Search on Page).
        if let pending = appState?.pendingFindOnPageRequest,
           pending.tabID == tabID {
            let coordinator = context.coordinator
            let trimmedQuery = pending.query.trimmingCharacters(in: .whitespacesAndNewlines)

            if coordinator.hasFindRequestInFlight() {
                coordinator.queueFindRequest(pending)
                DispatchQueue.main.async {
                    guard self.appState?.pendingFindOnPageRequest?.requestID == pending.requestID else { return }
                    self.appState?.pendingFindOnPageRequest = nil
                }
                didProcessPendingAction = true
            } else if coordinator.shouldDeferFindRequest(on: webView) {
                // Keep the request pending until WebKit is stable for find operations.
            } else if trimmedQuery.isEmpty {
                // Best-effort clear: remove any active selection/focus state tied to find.
                webView.evaluateJavaScript("window.getSelection().removeAllRanges();")
                DispatchQueue.main.async {
                    self.appState?.findOnPageMatchFound = nil
                    self.appState?.findOnPageMatchCount = nil
                    self.appState?.currentFindOnPageRequestID = nil
                    self.appState?.pendingFindOnPageRequest = nil
                }
                didProcessPendingAction = true
            } else {
                let configuration = WKFindConfiguration()
                configuration.caseSensitive = false
                configuration.wraps = true
                configuration.backwards = pending.backwards

                DispatchQueue.main.async {
                    self.appState?.currentFindOnPageRequestID = pending.requestID
                }
                coordinator.beginFindRequest(pending.requestID)

                webView.find(trimmedQuery, configuration: configuration) { result in
                    DispatchQueue.main.async {
                        defer {
                            if let queued = coordinator.completeFindRequest(pending.requestID),
                               self.appState?.pendingFindOnPageRequest == nil {
                                self.appState?.pendingFindOnPageRequest = queued
                            }
                        }
                        guard self.appState?.currentFindOnPageRequestID == pending.requestID else { return }
                        self.appState?.findOnPageMatchFound = result.matchFound
                    }
                }

                if appState?.findOnPageMatchCount == nil {
                    let requestID = pending.requestID
                    let queryLiteral = Self.javaScriptStringLiteral(trimmedQuery)
                    let countScript = """
                    (() => {
                        const q = \(queryLiteral);
                        if (!q || q.length === 0) { return 0; }
                        const haystack = (document.body && (document.body.innerText || document.body.textContent)) || "";
                        const needle = q.toLowerCase();
                        const text = haystack.toLowerCase();
                        let count = 0;
                        let idx = 0;
                        while (true) {
                            idx = text.indexOf(needle, idx);
                            if (idx === -1) { break; }
                            count += 1;
                            idx += needle.length;
                        }
                        return count;
                    })();
                    """

                    webView.evaluateJavaScript(countScript) { value, _ in
                        DispatchQueue.main.async {
                            guard self.appState?.currentFindOnPageRequestID == requestID else { return }
                            if let count = value as? Int {
                                self.appState?.findOnPageMatchCount = count
                            } else if let count = value as? Double {
                                self.appState?.findOnPageMatchCount = Int(count)
                            } else {
                                self.appState?.findOnPageMatchCount = 0
                            }
                        }
                    }
                }

                DispatchQueue.main.async {
                    self.appState?.pendingFindOnPageRequest = nil
                }
                didProcessPendingAction = true
            }
        }

        let hasPendingRehydrate = appState?.pendingHighlightRehydrate != nil
        if didProcessPendingAction && !hasPendingRehydrate { return }

        // Retry rehydrating a stale highlight
        if let pending = appState?.pendingHighlightRehydrate,
           !context.coordinator.isContentLoadInFlight,
           context.coordinator.canRunDocumentJavaScript(on: webView) {
            let payload: [String: Any] = [
                "id": pending.id.uuidString,
                "text": pending.text,
                "color": pending.cssColor,
                "contextBefore": pending.contextBefore,
                "contextAfter": pending.contextAfter
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload),
               let jsonString = String(data: data, encoding: .utf8) {
                let script = "window.retryHighlight(\(jsonString));"
                DispatchQueue.main.async {
                    self.appState?.isHighlightRehydrateInProgress = true
                }
                webView.evaluateJavaScript(script) { result, error in
                    if error != nil {
                        DispatchQueue.main.async {
                            context.coordinator.completePendingHighlightRehydrate(pending, success: false)
                        }
                        return
                    }

                    let success = result as? Bool ?? false
                    DispatchQueue.main.async {
                        context.coordinator.completePendingHighlightRehydrate(pending, success: success)
                    }
                }
            }

            DispatchQueue.main.async {
                self.appState?.pendingHighlightRehydrate = nil
            }
            return
        }

        // Only reload if document signature changed.
        let htmlSignature = contentRevision
        let shouldReloadContent =
            context.coordinator.lastLoadedArticleTitle != articleTitle ||
            context.coordinator.lastLoadedHTMLSignature != htmlSignature

        if shouldReloadContent {
            context.coordinator.tableOfContentsScrollRequestTracker.invalidate()
            let preparedHTMLContent = context.coordinator.prepareHTMLForInitialLoad(
                htmlContent,
                articleTitle: articleTitle,
                htmlSignature: htmlSignature
            )
            context.coordinator.lastLoadedArticleTitle = articleTitle
            context.coordinator.lastLoadedHTMLSignature = htmlSignature
            context.coordinator.configureRecoveryPayload(
                htmlContent: preparedHTMLContent,
                baseURL: baseURL
            )
            context.coordinator.highlightsApplied = false
            context.coordinator.lastAppliedHighlightIds = []
            context.coordinator.lastAppliedReaderAppearance = nil
            context.coordinator.lastAppliedReduceTransparency = nil
            context.coordinator.lastAppliedDifferentiateWithoutColor = nil
            context.coordinator.lastAppliedReaderTopInset = -1
            context.coordinator.lastKnownHighlightsCount = highlights.count
            context.coordinator.lastHighlightDiffCheckTimestamp = 0
            context.coordinator.lastAppliedSectionTrackingRequest = nil
            context.coordinator.lastAppliedRestoreTelemetryMode = nil
            context.coordinator.prepareForContentReload()
            webView.alphaValue = 0
            context.coordinator.beginContentReload(
                on: webView,
                htmlContent: preparedHTMLContent,
                baseURL: baseURL
            )
        } else {
            // SwiftUI can update the representable repeatedly while WebKit is
            // replacing its document. Document-end bridge functions do not
            // exist yet, so retrying them on every update can monopolize the
            // main thread and starve AppKit layout/accessibility work.
            guard !context.coordinator.isContentLoadInFlight,
                  context.coordinator.canRunDocumentJavaScript(on: webView) else { return }
            context.coordinator.restoreScrollPositionIfNeeded(on: webView, desiredY: scrollPosition)
            context.coordinator.applyReaderAppearance(to: webView)
            context.coordinator.syncScrollTelemetryMode(on: webView)
            context.coordinator.syncRestoreTelemetryMode(on: webView)
            context.coordinator.maybeApplyHighlightsIfNeeded(to: webView, highlights: highlights)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
        // Remove message handlers to break retain cycle between userContentController and coordinator.
        unregisterScriptMessageHandlers(from: nsView)
        guard !coordinator.contentLoadFailed else {
            nsView.stopLoading()
            return
        }
        WebViewPool.shared.store(
            nsView,
            for: coordinator.tabID,
            lastLoadedArticleTitle: coordinator.lastLoadedArticleTitle,
            lastLoadedHTMLSignature: coordinator.lastLoadedHTMLSignature,
            inspectorProjection: coordinator.inspectorProjection
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tabID: tabID,
            onLinkTapped: onLinkTapped,
            onOpenArticleInNewWindow: onOpenArticleInNewWindow,
            scrollPosition: $scrollPosition,
            onScrollProgress: onScrollProgress,
            fallbackScrollProgress: fallbackScrollProgress,
            appState: appState,
            modelContext: modelContext,
            onTextSelected: onTextSelected,
            onSelectionCleared: onSelectionCleared,
            highlights: highlights,
            articleTitle: articleTitle,
            contentRevision: contentRevision,
            readerAppearance: readerAppearance,
            reduceTransparency: reduceTransparency,
            differentiateWithoutColor: differentiateWithoutColor,
            readerTopInset: readerTopInset,
            preferImmediateReveal: preferImmediateReveal,
            onTableOfContentsUpdate: onTableOfContentsUpdate,
            onReferencesUpdate: onReferencesUpdate,
            onVisibleSectionChange: onVisibleSectionChange,
            onContentReveal: onContentReveal,
            onContentLoadFailure: onContentLoadFailure,
            onLinkHoverPreviewChange: onLinkHoverPreviewChange,
            linkPreviewImmediateModifier: linkPreviewImmediateModifier,
            nativeHighlightingMenuEnabled: nativeHighlightingMenuEnabled
        )
    }

    private static func registerScriptMessageHandlers(on webView: WKWebView, coordinator: Coordinator) {
        for name in scriptMessageHandlerNames {
            webView.configuration.userContentController.add(coordinator, name: name)
        }
    }

    private static func unregisterScriptMessageHandlers(from webView: WKWebView) {
        for name in scriptMessageHandlerNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let tabID: UUID
        var onLinkTapped: ((String) -> Void)?
        var onOpenArticleInNewWindow: ((Article) -> Void)?
        var onTextSelected: ((TextSelectionData) -> Void)?
        var onSelectionCleared: (() -> Void)?
        var scrollPosition: Binding<CGFloat>
        var onScrollProgress: ((Double) -> Void)?
        var fallbackScrollProgress: Double?
        var lastLoadedArticleTitle: String = ""
        var lastLoadedHTMLSignature: UInt64 = 0
        var recoveryHTMLPayload: String?
        var recoveryBaseURL: URL?
        var appState: AppState?
        var modelContext: ModelContext?
        var highlights: [Highlight] = []
        var articleTitle: String = ""
        var currentContentRevision: UInt64 = 0
        var highlightsApplied = false
        var lastAppliedHighlightIds: Set<UUID> = []
        var readerAppearance: ReaderAppearance
        var reduceTransparency: Bool
        var differentiateWithoutColor: Bool
        var readerTopInset: CGFloat
        var preferImmediateReveal: Bool
        var onTableOfContentsUpdate: (([ArticleTableOfContentsItem]) -> Void)?
        var onReferencesUpdate: (([ArticleReferenceSection]) -> Void)?
        var onVisibleSectionChange: ((String?) -> Void)?
        var onContentReveal: (() -> Void)?
        var onContentLoadFailure: ((Error) -> Void)?
        var onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?
        var linkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier
        var nativeHighlightingMenuEnabled: Bool
        var openTimer: Binding<ArticleOpenTimer>?

        func canRunDocumentJavaScript(on webView: WKWebView) -> Bool {
            !webView.isLoading && !contentLoadFailed
        }
        var lastAppliedReaderAppearance: ReaderAppearance?
        var lastAppliedReduceTransparency: Bool?
        var lastAppliedDifferentiateWithoutColor: Bool?
        var lastAppliedReaderTopInset: CGFloat = -1
        var lastAppliedLinkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier?
        var lastAppliedNativeHighlightingMenuEnabled: Bool?
        var lastAppliedSectionTrackingRequest: Bool?
        var lastAppliedRestoreTelemetryMode: Bool?
        weak var webView: WKWebView?
        var lastHighlightDiffCheckTimestamp: TimeInterval = 0
        var lastKnownHighlightsCount: Int = 0
        let inspectorPublisher = WebViewInspectorPublisher()
        var inspectorProjection = WebViewPool.InspectorProjection.empty
        var inspectorProjectionGeneration: UInt64 = 0
        let tableOfContentsScrollRequestTracker = WebViewTableOfContentsScrollRequestTracker()
        var lastReportedProgress: Double = -1
        var lastProgressTimestamp: TimeInterval = 0
        var lastKnownScrollY: CGFloat = 0
        var highVelocityUserScrollUntil: TimeInterval = 0
        var lastProgrammaticScrollTimestamp: TimeInterval = 0
        var programmaticScrollActiveUntil: TimeInterval = 0
        var hasProgrammaticScrollInFlight = false
        var lastJSTelemetryTimestamp: TimeInterval = 0
        var initialTelemetryGuard = WebViewScrollRestoreController.InitialTelemetryGuard.inactive
        var hasUserDrivenScrollSinceLoad = false
        var isContentLoadInFlight = false
        var expectedNavigationToken: ObjectIdentifier?
        var activeRestoreSessionID: UUID?
        var webContentTerminationCount = 0
        var contentLoadFailed = false
        var hasReportedContentReveal = false
        var pendingPostRevealTasks: [() -> Void] = []
        var lastSaveRequestTimestamp: TimeInterval = 0
        var lastScrollPositionPublishTimestamp: TimeInterval = 0
        var lastHandledLinkSignature: String?
        var lastHandledLinkTimestamp: TimeInterval = 0
        var lastHandledAnyLinkTimestamp: TimeInterval = 0
        var adaptiveScrollDeltaThreshold: CGFloat = 14
        var adaptiveScrollTimeGate: TimeInterval = 0.9
        var adaptiveProgressDeltaThreshold: Double = 0.045
        var adaptiveProgressTimeGate: TimeInterval = 1.6
        var adaptiveSaveRequestInterval: TimeInterval = 3.4
        var currentScrollProfile: ScrollProfile = .balanced
        var isFindRequestInFlight = false
        var activeFindRequestID: UUID?
        var queuedFindRequest: AppState.FindOnPageRequest?
        var findRequestTimeoutWorkItem: DispatchWorkItem?
        var pendingLinkHoverHideWorkItem: DispatchWorkItem?
        var activeLinkHoverSignature: String?
        var isHoveringLinkPreviewSource = false
        var isHoveringLinkPreviewOverlay = false
        var lastPublishedLinkHoverPreview: WebViewLinkHoverRequest?
        var preparedHTMLCache = PreparedHTMLTransformCache()
        private let maxRecoveryHTMLBytes = 420_000
        private let eagerImageCountForInitialLoad = 3
        private let findRequestTimeoutSeconds: TimeInterval = 1.6
        private static let imgTagRegex = try? NSRegularExpression(
            pattern: "<img\\b[^>]*>",
            options: [.caseInsensitive]
        )
        /// Appearance baked into the documentStart bootstrap WKUserScript.
        /// We still sync post-load so top-inset updates remain deterministic.
        var bootstrapAppearance: ReaderAppearance?

        init(
            tabID: UUID,
            onLinkTapped: ((String) -> Void)?,
            onOpenArticleInNewWindow: ((Article) -> Void)?,
            scrollPosition: Binding<CGFloat>,
            onScrollProgress: ((Double) -> Void)?,
            fallbackScrollProgress: Double?,
            appState: AppState?,
            modelContext: ModelContext?,
            onTextSelected: ((TextSelectionData) -> Void)?,
            onSelectionCleared: (() -> Void)?,
            highlights: [Highlight],
            articleTitle: String,
            contentRevision: UInt64,
            readerAppearance: ReaderAppearance,
            reduceTransparency: Bool = false,
            differentiateWithoutColor: Bool = false,
            readerTopInset: CGFloat,
            preferImmediateReveal: Bool,
            onTableOfContentsUpdate: (([ArticleTableOfContentsItem]) -> Void)?,
            onReferencesUpdate: (([ArticleReferenceSection]) -> Void)?,
            onVisibleSectionChange: ((String?) -> Void)?,
            onContentReveal: (() -> Void)?,
            onContentLoadFailure: ((Error) -> Void)? = nil,
            onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?,
            linkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier,
            nativeHighlightingMenuEnabled: Bool
        ) {
            self.tabID = tabID
            self.onLinkTapped = onLinkTapped
            self.onOpenArticleInNewWindow = onOpenArticleInNewWindow
            self.scrollPosition = scrollPosition
            self.onScrollProgress = onScrollProgress
            self.fallbackScrollProgress = fallbackScrollProgress
            self.appState = appState
            self.modelContext = modelContext
            self.onTextSelected = onTextSelected
            self.onSelectionCleared = onSelectionCleared
            self.highlights = highlights
            self.articleTitle = articleTitle
            self.currentContentRevision = contentRevision
            self.readerAppearance = readerAppearance
            self.reduceTransparency = reduceTransparency
            self.differentiateWithoutColor = differentiateWithoutColor
            self.readerTopInset = readerTopInset
            self.preferImmediateReveal = preferImmediateReveal
            self.onTableOfContentsUpdate = onTableOfContentsUpdate
            self.onReferencesUpdate = onReferencesUpdate
            self.onVisibleSectionChange = onVisibleSectionChange
            self.onContentReveal = onContentReveal
            self.onContentLoadFailure = onContentLoadFailure
            self.onLinkHoverPreviewChange = onLinkHoverPreviewChange
            self.linkPreviewImmediateModifier = linkPreviewImmediateModifier
            self.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
            super.init()
        }

        @MainActor
        func attachNewWebView(_ webView: WKWebView) {
            self.webView = webView
        }

        @MainActor
        func attachReusedWebView(
            _ webView: WKWebView,
            inspectorProjection: WebViewPool.InspectorProjection
        ) {
            tableOfContentsScrollRequestTracker.invalidate()
            dismissLinkHoverPreview(immediate: true)
            cancelScriptedScrollRestore(on: webView)
            isContentLoadInFlight = false
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            self.webView = webView
            lastAppliedReduceTransparency = nil
            lastAppliedDifferentiateWithoutColor = nil
            syncReaderAccessibilityStyle(on: webView)
            syncRestoreTelemetryMode(on: webView, force: true)
            restoreInspectorProjection(inspectorProjection, on: webView)
            if webView.alphaValue < 1 {
                webView.alphaValue = 1
            }
            hasReportedContentReveal = true
            onContentReveal?()
        }

        func applyHighlights(to webView: WKWebView) {
            // Handle empty highlights (remove all marks from DOM)
            if highlights.isEmpty {
                let script = "window.applyHighlights([]);"
                webView.evaluateJavaScript(script) { [weak self] _, _ in
                    self?.highlightsApplied = true
                    self?.lastAppliedHighlightIds = []
                    self?.lastKnownHighlightsCount = 0
                }
                return
            }

            let highlightData = highlights.map { h -> [String: Any] in
                [
                    "id": h.id.uuidString,
                    "text": h.text,
                    "elementPath": h.elementPath ?? "",
                    "startOffset": h.startOffset,
                    "color": h.color.cssColor,
                    "contextBefore": h.contextBefore ?? "",
                    "contextAfter": h.contextAfter ?? ""
                ]
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: highlightData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return
            }

            let script = "window.applyHighlights(\(jsonString));"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error == nil {
                    self?.highlightsApplied = true
                    self?.lastAppliedHighlightIds = Set(self?.highlights.map { $0.id } ?? [])
                    self?.lastKnownHighlightsCount = self?.highlights.count ?? 0
                }
            }
        }

        func maybeApplyHighlightsIfNeeded(to webView: WKWebView, highlights: [Highlight]) {
            let now = Date().timeIntervalSinceReferenceDate
            let countChanged = highlights.count != lastKnownHighlightsCount
            if highlightsApplied, !countChanged, (now - lastJSTelemetryTimestamp) < 0.55 {
                return
            }
            let shouldCheckIds = !highlightsApplied || countChanged || (now - lastHighlightDiffCheckTimestamp) > 1.1
            guard shouldCheckIds else { return }

            lastHighlightDiffCheckTimestamp = now
            lastKnownHighlightsCount = highlights.count

            let currentHighlightIds = Set(highlights.map { $0.id })
            let highlightsChanged = currentHighlightIds != lastAppliedHighlightIds
            if highlightsChanged || (!highlightsApplied && !highlights.isEmpty) {
                applyHighlights(to: webView)
            }
        }

        @MainActor
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {

            // Check the URL
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // 1. Detect internal Wikipedia article targets.
            if let target = wikipediaLinkTarget(from: url) {
                let isUserInitiatedLink =
                    navigationAction.navigationType == .linkActivated ||
                    navigationAction.targetFrame == nil
                if !isUserInitiatedLink {
                    decisionHandler(.allow)
                    return
                }

                let hasFragment = !(url.fragment?.isEmpty ?? true)
                let isCurrentArticle = normalizedArticleKey(target.displayTitle) == normalizedArticleKey(articleTitle)

                // Preserve native in-page anchor behavior for same-article fragment links.
                if isCurrentArticle && hasFragment {
                    decisionHandler(.allow)
                    return
                }

                let optionClick = navigationAction.modifierFlags.contains(.option)
                let openInNewTab = navigationAction.modifierFlags.contains(.command) && !optionClick
                if !shouldHandleLink(url: url, newTab: openInNewTab, optionSave: optionClick) {
                    decisionHandler(.cancel)
                    return
                }

                decisionHandler(.cancel)
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if optionClick {
                        let article = Article(id: target.id, title: target.displayTitle)
                        self.appState?.presentOptionClickSavePrompt(for: article)
                    } else if openInNewTab {
                        let article = Article(id: target.id, title: target.displayTitle)
                        self.appState?.openArticleInNewTab(article, activate: false)
                    } else {
                        self.onLinkTapped?(target.displayTitle)
                    }
                }
                return
            }

            // 2. Apply a deny-by-default scheme policy to non-Wikipedia navigation.
            // Fetched article HTML is untrusted input; it must not be able to navigate the
            // reader to javascript:, file:, or arbitrary custom schemes.
            let isUserInitiated =
                navigationAction.navigationType == .linkActivated ||
                navigationAction.targetFrame == nil
            switch WebViewNavigationPolicy.disposition(for: url, isUserInitiated: isUserInitiated) {
            case .allowInWebView:
                decisionHandler(.allow)
            case .openExternally:
                _ = SystemBridge.openURLExternally(url)
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Route target="_blank" requests back through the normal navigation policy.
            if navigationAction.request.url != nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        @MainActor
        func cleanup() {
            appState = nil
            webView = nil
            tableOfContentsScrollRequestTracker.invalidate()
            findRequestTimeoutWorkItem?.cancel()
            findRequestTimeoutWorkItem = nil
            dismissLinkHoverPreview(immediate: true)
        }

        func shouldDeferFindRequest(on webView: WKWebView) -> Bool {
            isContentLoadInFlight || webView.isLoading || webView.url == nil
        }

        func hasFindRequestInFlight() -> Bool {
            isFindRequestInFlight
        }

        func queueFindRequest(_ request: AppState.FindOnPageRequest) {
            queuedFindRequest = request
        }

        func beginFindRequest(_ requestID: UUID) {
            isFindRequestInFlight = true
            activeFindRequestID = requestID
            findRequestTimeoutWorkItem?.cancel()

            let timeoutWorkItem = DispatchWorkItem { [weak self] in
                guard let self, self.activeFindRequestID == requestID else { return }
                _ = self.completeFindRequest(requestID)
            }
            findRequestTimeoutWorkItem = timeoutWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + findRequestTimeoutSeconds,
                execute: timeoutWorkItem
            )
        }

        @discardableResult
        func completeFindRequest(_ requestID: UUID) -> AppState.FindOnPageRequest? {
            guard activeFindRequestID == requestID else { return nil }
            isFindRequestInFlight = false
            activeFindRequestID = nil
            findRequestTimeoutWorkItem?.cancel()
            findRequestTimeoutWorkItem = nil
            let queued = queuedFindRequest
            queuedFindRequest = nil
            return queued
        }

        func configureRecoveryPayload(htmlContent: String, baseURL: URL?) {
            if htmlContent.utf8.count <= maxRecoveryHTMLBytes {
                recoveryHTMLPayload = htmlContent
                recoveryBaseURL = baseURL
            } else {
                recoveryHTMLPayload = nil
                recoveryBaseURL = baseURL
            }
        }

        func prepareHTMLForInitialLoad(
            _ htmlContent: String,
            articleTitle: String,
            htmlSignature: UInt64
        ) -> String {
            let byteCount = htmlContent.utf8.count
            let cacheKey = preparedHTMLCacheKey(
                articleTitle: articleTitle,
                htmlSignature: htmlSignature,
                byteCount: byteCount
            )

            if let cached = preparedHTMLCache.cachedEntry(forKey: cacheKey) {
                switch cached {
                case .passthrough:
                    return htmlContent
                case .rewritten(let preparedHTML):
                    return preparedHTML
                }
            }

            guard htmlContent.range(of: "<img", options: .caseInsensitive) != nil,
                  let regex = Self.imgTagRegex else {
                preparedHTMLCache.store(.passthrough, forKey: cacheKey)
                return htmlContent
            }

            let source = htmlContent as NSString
            let matches = regex.matches(in: htmlContent, range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else {
                preparedHTMLCache.store(.passthrough, forKey: cacheKey)
                return htmlContent
            }

            var rewritten = htmlContent
            var locationOffset = 0
            var didRewriteAnyTag = false

            for (index, match) in matches.enumerated() {
                let adjustedRange = NSRange(
                    location: match.range.location + locationOffset,
                    length: match.range.length
                )
                guard let swiftRange = Range(adjustedRange, in: rewritten) else { continue }
                var tag = String(rewritten[swiftRange])

                let shouldBeEager = index < eagerImageCountForInitialLoad
                let desiredLoadingValue = shouldBeEager ? "eager" : "lazy"
                let desiredFetchPriority = shouldBeEager ? "high" : "auto"
                var didMutate = false

                if !containsHTMLAttribute("loading", in: tag) {
                    tag = insertHTMLAttribute(name: "loading", value: desiredLoadingValue, into: tag)
                    didMutate = true
                }
                if !containsHTMLAttribute("decoding", in: tag) {
                    tag = insertHTMLAttribute(name: "decoding", value: "async", into: tag)
                    didMutate = true
                }
                if !containsHTMLAttribute("fetchpriority", in: tag) {
                    tag = insertHTMLAttribute(name: "fetchpriority", value: desiredFetchPriority, into: tag)
                    didMutate = true
                }

                guard didMutate else { continue }
                didRewriteAnyTag = true
                let previousLength = adjustedRange.length
                rewritten.replaceSubrange(swiftRange, with: tag)
                locationOffset += (tag as NSString).length - previousLength
            }

            guard didRewriteAnyTag else {
                preparedHTMLCache.store(.passthrough, forKey: cacheKey)
                return htmlContent
            }

            preparedHTMLCache.store(.rewritten(rewritten), forKey: cacheKey)
            return rewritten
        }

        private func preparedHTMLCacheKey(
            articleTitle: String,
            htmlSignature: UInt64,
            byteCount: Int
        ) -> String {
            "\(articleTitle)|\(String(htmlSignature, radix: 16))|\(byteCount)"
        }

        private func containsHTMLAttribute(_ name: String, in tag: String) -> Bool {
            let pattern = #"\b\#(name)\s*="#
            return tag.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        }

        private func insertHTMLAttribute(name: String, value: String, into tag: String) -> String {
            guard let closingIndex = tag.lastIndex(of: ">") else { return tag }
            var insertionIndex = closingIndex
            if let slashIndex = tag.index(closingIndex, offsetBy: -1, limitedBy: tag.startIndex),
               tag[slashIndex] == "/" {
                insertionIndex = slashIndex
            }
            var updated = tag
            updated.insert(
                contentsOf: " \(name)=\"\(value)\"",
                at: insertionIndex
            )
            return updated
        }

    }
}

/// Convenience initializer without scroll position binding
extension WebView {
    init(
        htmlContent: String,
        tabID: UUID = UUID(),
        articleTitle: String = "",
        baseURL: URL? = URL(string: "https://en.wikipedia.org/wiki/"),
        onLinkTapped: ((String) -> Void)? = nil
    ) {
        self.tabID = tabID
        self.htmlContent = htmlContent
        self.contentRevision = ReaderDocumentRevision.digest(for: htmlContent)
        self.articleTitle = articleTitle
        self.baseURL = baseURL
        self.onLinkTapped = onLinkTapped
        self.onOpenArticleInNewWindow = nil
        self._scrollPosition = .constant(0)
        self.fallbackScrollProgress = nil
    }

    static func makeReaderAppearanceBootstrapScript(from payload: [String: String]) -> String {
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload))
        let payloadJSON = payloadData.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        (function() {
            var appearance = \(payloadJSON);
            function apply() {
                var root = document.documentElement;
                if (!root) return;

                function setVar(optionKey, cssVarName) {
                    if (!Object.prototype.hasOwnProperty.call(appearance, optionKey)) return;
                    var value = appearance[optionKey];
                    if (value === undefined || value === null) return;
                    root.style.setProperty(cssVarName, String(value));
                }

                setVar('bodyFontFamily', '--reader-body-font');
                setVar('headingFontFamily', '--reader-heading-font');
                setVar('fontSize', '--reader-font-size');
                setVar('lineHeight', '--reader-line-height');
                setVar('paragraphSpacing', '--reader-paragraph-spacing');
                setVar('contentWidth', '--reader-max-width');
                setVar('inlinePadding', '--reader-inline-padding');
                setVar('headingScale', '--reader-heading-scale');
            }

            function applyThemeClasses() {
                var root = document.documentElement;
                if (!root) return;
                var prefersDark = false;
                if (window.matchMedia) {
                    prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
                }
                root.classList.toggle('pcs-theme-dark', prefersDark);
                root.classList.toggle('skin-theme-clientpref-os', prefersDark);
            }

            function bindThemeListener() {
                if (!window.matchMedia) return;
                var media = window.matchMedia('(prefers-color-scheme: dark)');
                if (media.addEventListener) {
                    media.addEventListener('change', applyThemeClasses);
                } else if (media.addListener) {
                    media.addListener(applyThemeClasses);
                }
            }

            apply();
            applyThemeClasses();
            bindThemeListener();
            document.addEventListener('DOMContentLoaded', function() {
                apply();
                applyThemeClasses();
            }, { once: true });
        })();
        """
    }
}

enum ScrollProfile {
    case responsive
    case balanced
    case economy
}
