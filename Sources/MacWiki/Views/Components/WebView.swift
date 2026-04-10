import SwiftUI
import AppKit
import WebKit
import SwiftData

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

    /// Article title for highlight association
    let articleTitle: String

    /// Base URL for resolving relative links (must end in /wiki/ for ./ links to work)
    var baseURL: URL? = URL(string: "https://en.wikipedia.org/wiki/")

    /// Callback when a Wikipedia link is tapped
    var onLinkTapped: ((String) -> Void)?

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

    /// Callback when the reader should show or hide a floating link-hover preview.
    var onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?

    /// Whether the SwiftUI hover-preview overlay is currently hovered.
    var linkHoverPreviewOverlayHovering: Bool = false

    /// Signature of the hover-preview overlay currently presented by SwiftUI.
    var activeLinkHoverPreviewSignature: String?

    /// Enables native context-menu driven text highlighting interactions.
    var nativeHighlightingMenuEnabled: Bool = false

    /// Optional open-path timer for phase instrumentation.
    var openTimer: Binding<ArticleOpenTimer>?

    // Dependencies for Context Menu
    var appState: AppState?

    // Explicit dependencies for reactivity
    // Since AppState is a reference type, changes to its properties don't invalidate
    // the WebView struct unless we bind specific values we care about.
    var inspectorVisible: Bool = false
    var inspectorMode: InspectorMode = .info
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

    /// Lightweight content signature for reload detection.
    /// Uses sampled prefix/suffix bytes plus total length to avoid expensive full-string comparisons.
    private static func htmlReloadSignature(for html: String) -> UInt64 {
        let utf8 = html.utf8
        let byteCount = utf8.count
        var hash: UInt64 = 1469598103934665603

        @inline(__always)
        func mix(_ byte: UInt8, into hash: inout UInt64) {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }

        for byte in utf8.prefix(512) {
            mix(byte, into: &hash)
        }

        if byteCount > 1024 {
            mix(0xFF, into: &hash)
            for byte in utf8.suffix(512) {
                mix(byte, into: &hash)
            }
        }

        var length = UInt64(byteCount)
        withUnsafeBytes(of: &length) { bytes in
            for byte in bytes {
                mix(byte, into: &hash)
            }
        }

        return hash
    }

    /// Encodes a Swift string as a safe JavaScript string literal.
    private static func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }


    func makeNSView(context: Context) -> WKWebView {
        if let checkout = WebViewPool.shared.checkout(for: tabID) {
            let webView = checkout.webView
            webView.navigationDelegate = context.coordinator
            webView.uiDelegate = context.coordinator
            context.coordinator.bootstrapAppearance = readerAppearance
            context.coordinator.lastLoadedArticleTitle = checkout.lastLoadedArticleTitle
            context.coordinator.lastLoadedHTMLSignature = checkout.lastLoadedHTMLSignature
            Self.unregisterScriptMessageHandlers(from: webView)
            Self.registerScriptMessageHandlers(on: webView, coordinator: context.coordinator)
            context.coordinator.attachReusedWebView(webView)
            return webView
        }

        let configuration = WKWebViewConfiguration()

        // Enable content blocking for cleaner display
        configuration.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
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
        context.coordinator.bootstrapAppearance = readerAppearance

        // Inject custom CSS for native reader aesthetic
        let css = """
        :root {
            color-scheme: light dark;
            --text-primary: #1d1d1f;
            --text-secondary: #6e6e73;
            --link-color: #0066cc;
            --bg-subtle: rgba(0, 0, 0, 0.03);
            --border-color: rgba(0, 0, 0, 0.08);
            --table-surface: rgba(0, 0, 0, 0.02);
            --table-header-surface: rgba(0, 0, 0, 0.05);
            --table-row-stripe: rgba(0, 0, 0, 0.03);
            --reader-surface: #ffffff;
            --reader-body-font: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
            --reader-heading-font: -apple-system, BlinkMacSystemFont, 'SF Pro Display', sans-serif;
            --reader-font-size: 17px;
            --reader-line-height: 1.65;
            --reader-paragraph-spacing: 16px;
            --reader-max-width: 920px;
            --reader-inline-padding: 40px;
            --reader-inline-padding-safe: min(
                var(--reader-inline-padding),
                max(12px, calc((100vw - \(Int(ReaderAppearance.minimumReadableColumnWidth.rounded()))px) / 2))
            );
            --reader-heading-scale: 1;
            --reader-top-inset: \(Int(readerTopInset.rounded()))px;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --text-primary: #f5f5f7;
                --text-secondary: #a1a1a6;
                --link-color: #6cb4ff;
                --bg-subtle: rgba(255, 255, 255, 0.05);
                --border-color: rgba(255, 255, 255, 0.1);
                --table-surface: rgba(255, 255, 255, 0.04);
                --table-header-surface: rgba(255, 255, 255, 0.09);
                --table-row-stripe: rgba(255, 255, 255, 0.06);
                --reader-surface: #1e2434;
                --chart-axis-text: rgba(234, 237, 245, 0.88);
                --chart-line-strong: rgba(255, 255, 255, 0.50);
                --chart-line-grid: rgba(255, 255, 255, 0.26);
                /* Bridge Wikimedia PCS tokens to MacWiki palette for dark mode. */
                --background-color-base: var(--reader-surface);
                --background-color-neutral-subtle: var(--table-surface);
                --background-color-neutral: color-mix(in srgb, var(--reader-surface) 84%, white 16%);
                --color-base: var(--text-primary);
                --color-emphasized: var(--text-primary);
                --color-subtle: var(--text-secondary);
                --color-progressive: var(--link-color);
                --border-color-base: var(--border-color);
                --border-color-subtle: var(--border-color);
                --box-shadow-collapse-table: none;
            }

            /* Force readable text when source HTML hardcodes dark text colors. */
            body,
            .pcs-document,
            .pcs-section,
            .pcs-section-block,
            .mw-parser-output,
            p, li, dd, dt, blockquote, td, th, caption, figcaption, span {
                color: var(--text-primary) !important;
            }

            [style*="color:#202122"],
            [style*="color: #202122"],
            [style*="color:rgb(32,33,34)"],
            [style*="color: rgb(32, 33, 34)"],
            [style*="color:#000"],
            [style*="color: #000"],
            [style*="color:black"],
            [style*="color: black"] {
                color: var(--text-primary) !important;
            }

            a, a * {
                color: var(--link-color) !important;
            }

            /* Override light inline table backgrounds that wash out in dark mode. */
            table {
                background-color: var(--table-surface) !important;
                border-color: var(--border-color) !important;
                color: var(--text-primary) !important;
            }

            table thead,
            table tbody,
            table tfoot,
            table caption,
            table colgroup,
            table col,
            table tr,
            table td,
            table th {
                background-color: var(--table-surface) !important;
                background-image: none !important;
                border-color: var(--border-color) !important;
                color: var(--text-primary) !important;
            }

            table th {
                background-color: var(--table-header-surface) !important;
            }

            table.wikitable,
            .wikitable,
            table.wikitable tr,
            table.wikitable td,
            table.wikitable th {
                background-color: var(--table-surface) !important;
            }

            table.infobox,
            .infobox,
            .infobox-full-data {
                background-color: var(--bg-subtle) !important;
            }

            table tbody tr:nth-child(even) td,
            table tbody tr:nth-child(even) th {
                background-color: var(--table-row-stripe) !important;
            }

            /* Remap common Wikipedia light table colors to dark-friendly surfaces. */
            table [style*="background:#fff"],
            table [style*="background: #fff"],
            table [style*="background-color:#fff"],
            table [style*="background-color: #fff"],
            table [style*="background:#ffffff"],
            table [style*="background: #ffffff"],
            table [style*="background-color:#ffffff"],
            table [style*="background-color: #ffffff"],
            table [style*="background:rgb(255,255,255)"],
            table [style*="background: rgb(255, 255, 255)"],
            table [style*="background-color:rgb(255,255,255)"],
            table [style*="background-color: rgb(255, 255, 255)"],
            table [style*="background:#f8f9fa"],
            table [style*="background: #f8f9fa"],
            table [style*="background-color:#f8f9fa"],
            table [style*="background-color: #f8f9fa"],
            table [style*="background:#eaecf0"],
            table [style*="background: #eaecf0"],
            table [style*="background-color:#eaecf0"],
            table [style*="background-color: #eaecf0"] {
                background-color: var(--table-surface) !important;
            }

            table th[style*="background:#eaecf0"],
            table th[style*="background: #eaecf0"],
            table th[style*="background-color:#eaecf0"],
            table th[style*="background-color: #eaecf0"] {
                background-color: var(--table-header-surface) !important;
            }

            table td a,
            table th a {
                color: var(--link-color) !important;
            }

            /*
             Improve readability for embedded Wikipedia SVG charts/timelines.
             Some charts hardcode dark fills (black/#000), which disappear on dark surfaces.
             Keep authored non-dark colors intact, only remap near-black text/strokes.
            */
            svg text[fill="#000"],
            svg text[fill="#000000"],
            svg text[fill="black"],
            svg text[style*="fill:#000"],
            svg text[style*="fill: #000"],
            svg text[style*="fill:black"],
            svg text[style*="fill: black"] {
                fill: var(--chart-axis-text) !important;
            }

            svg text[stroke="#000"],
            svg text[stroke="#000000"],
            svg text[stroke="black"],
            svg text[style*="stroke:#000"],
            svg text[style*="stroke: #000"],
            svg text[style*="stroke:black"],
            svg text[style*="stroke: black"] {
                stroke: transparent !important;
            }

            svg line[stroke="#000"],
            svg line[stroke="#000000"],
            svg line[stroke="black"],
            svg path[stroke="#000"],
            svg path[stroke="#000000"],
            svg path[stroke="black"],
            svg polyline[stroke="#000"],
            svg polyline[stroke="#000000"],
            svg polyline[stroke="black"],
            svg g[style*="stroke:#000"],
            svg g[style*="stroke: #000"],
            svg g[style*="stroke:black"],
            svg g[style*="stroke: black"] {
                stroke: var(--chart-line-strong) !important;
            }

            svg [class*="grid"][stroke="#000"],
            svg [class*="grid"][stroke="#000000"],
            svg [class*="grid"][stroke="black"],
            svg [class*="tick"][stroke="#000"],
            svg [class*="tick"][stroke="#000000"],
            svg [class*="tick"][stroke="black"],
            svg [class*="grid"][style*="stroke:#000"],
            svg [class*="grid"][style*="stroke: #000"],
            svg [class*="grid"][style*="stroke:black"],
            svg [class*="grid"][style*="stroke: black"],
            svg [class*="tick"][style*="stroke:#000"],
            svg [class*="tick"][style*="stroke: #000"],
            svg [class*="tick"][style*="stroke:black"],
            svg [class*="tick"][style*="stroke: black"] {
                stroke: var(--chart-line-grid) !important;
            }
        }

        * {
            box-sizing: border-box;
        }

        html {
            background-color: var(--reader-surface) !important;
        }

        body,
        .pcs-document,
        .mw-parser-output {
            color: var(--text-primary) !important;
            background-color: var(--reader-surface) !important;
        }

        body {
            font-family: var(--reader-body-font);
            font-size: var(--reader-font-size);
            line-height: var(--reader-line-height);
            color: var(--text-primary) !important;
            background: var(--reader-surface) !important;
            width: min(var(--reader-max-width), calc(100% - (var(--reader-inline-padding-safe) * 2)));
            max-width: 100%;
            padding: var(--reader-top-inset) 0 60px;
            margin: 0 auto;
            -webkit-font-smoothing: antialiased;
            text-rendering: auto;
        }

        /* Hide Wikipedia chrome */
        .mw-footer, .pcs-footer-container, .pcs-edit-section-link,
        .mw-ref-link, .sistersitebox, .navbox, .ambox, .mbox-small,
        .metadata, .hatnote, .noprint, .mw-editsection {
            display: none !important;
        }

        /* CRITICAL: Expand all collapsed sections (Wikipedia mobile-html) */
        .pcs-section-block, .pcs-collapse-block, section {
            display: block !important;
            max-height: none !important;
            overflow: visible !important;
        }

        /* Ensure collapsed content is visible */
        [hidden], .pcs-hidden, .collapsed {
            display: block !important;
            visibility: visible !important;
        }

        /* Expand section content */
        .pcs-section-content {
            display: block !important;
            height: auto !important;
            max-height: none !important;
        }

        /* Typography */
        h1 {
            font-family: var(--reader-heading-font);
            font-size: calc(34px * var(--reader-heading-scale));
            font-weight: 700;
            line-height: 1.2;
            letter-spacing: -0.5px;
            margin: 0 0 8px 0;
        }

        h2 {
            font-family: var(--reader-heading-font);
            font-size: calc(24px * var(--reader-heading-scale));
            font-weight: 600;
            line-height: 1.3;
            margin: 32px 0 12px 0;
            padding-bottom: 8px;
            border-bottom: 1px solid var(--border-color);
        }

        h3 {
            font-family: var(--reader-heading-font);
            font-size: calc(20px * var(--reader-heading-scale));
            font-weight: 600;
            margin: 24px 0 8px 0;
        }

        p, .pcs-section p, .pcs-section-block p, .mw-parser-output p {
            margin-top: 0 !important;
            margin-bottom: var(--reader-paragraph-spacing) !important;
        }

        /* Links */
        a {
            color: var(--link-color) !important;
            text-decoration: none;
            transition: opacity 0.15s ease;
        }

        a:hover {
            opacity: 0.8;
        }

        /* Images */
        @keyframes macwiki-image-skeleton-shimmer {
            0% { background-position: 0% 0; }
            100% { background-position: 200% 0; }
        }

        img {
            max-width: 100%;
            height: auto;
            border-radius: 8px;
            margin: 16px 0;
            background-color: var(--bg-subtle);
        }

        img[data-macwiki-image-transition="1"] {
            opacity: 1;
            transition: opacity 0.22s ease-out, filter 0.22s ease-out;
        }

        html.macwiki-fast-scroll img[data-macwiki-image-transition="1"] {
            transition: none !important;
        }

        img[data-macwiki-image-transition="1"][data-macwiki-image-skeleton="1"][data-macwiki-image-state="loading"] {
            opacity: 1;
            background-image: linear-gradient(
                100deg,
                color-mix(in srgb, var(--bg-subtle) 86%, transparent) 0%,
                color-mix(in srgb, white 18%, var(--bg-subtle) 82%) 38%,
                color-mix(in srgb, var(--bg-subtle) 86%, transparent) 72%
            );
            background-size: 220% 100%;
            animation: macwiki-image-skeleton-shimmer 1.25s linear infinite;
            filter: saturate(0.92) contrast(0.96);
        }

        img[data-macwiki-image-transition="1"][data-macwiki-image-skeleton="0"][data-macwiki-image-state="loading"] {
            opacity: 0;
        }

        img[data-macwiki-image-state="loading"] {
            border: 1px solid color-mix(in srgb, var(--border-color) 84%, transparent);
        }

        img[data-macwiki-image-state="loaded"] {
            opacity: 1;
            filter: none;
            animation: none;
        }

        html.macwiki-fast-scroll img[data-macwiki-image-transition="1"][data-macwiki-image-skeleton="1"][data-macwiki-image-state="loading"] {
            animation: none !important;
            background-position: 50% 0;
            filter: none;
        }

        @media (prefers-reduced-motion: reduce) {
            img[data-macwiki-image-transition="1"] {
                transition: none;
            }
            img[data-macwiki-image-transition="1"][data-macwiki-image-skeleton="1"][data-macwiki-image-state="loading"] {
                animation: none;
            }
        }

        figure {
            margin: 24px 0;
            padding: 0;
        }

        figcaption {
            font-size: 14px;
            color: var(--text-secondary);
            margin-top: 8px;
            line-height: 1.4;
        }

        /* Infobox styling */
        .infobox, .infobox-full-data, table.infobox {
            background: var(--bg-subtle);
            border-radius: 12px;
            padding: 16px;
            border: 1px solid var(--border-color) !important;
            margin: 0 0 24px 24px;
            float: right;
            max-width: 300px;
        }

        .infobox th, .infobox td {
            border: none !important;
            padding: 4px 8px;
        }

        /* Block quotes */
        blockquote {
            margin: 24px 0;
            padding: 16px 24px;
            background: var(--bg-subtle);
            border-left: 3px solid var(--link-color);
            border-radius: 0 8px 8px 0;
            font-style: italic;
        }

        /* Lists */
        ul, ol {
            margin: 16px 0;
            padding-left: 24px;
        }

        li {
            margin: 8px 0;
        }

        /* Hide reference sections in reader — surfaced in Inspector instead */
        html.macwiki-hide-reference-sections section.macwiki-reference-section {
            display: none !important;
        }

        html.macwiki-hide-reference-sections .mw-references-wrap {
            display: none !important;
        }

        /* Tables */
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 24px 0;
            font-size: 15px;
            background: var(--table-surface);
        }

        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid var(--border-color);
        }

        th {
            font-weight: 600;
            background: var(--table-header-surface);
        }

        /* Collapsible tables (Wikipedia mobile PCS) */
        .pcs-collapse-table-container {
            background: var(--table-surface) !important;
            border: 1px solid var(--border-color) !important;
            border-radius: 12px;
            box-shadow: none !important;
            overflow: hidden;
        }

        .pcs-collapse-table-collapsed-container,
        .pcs-collapse-table-collapsed-bottom {
            background: var(--table-surface) !important;
            color: var(--text-secondary) !important;
        }

        .pcs-collapse-table-collapsed-container {
            border-bottom: 1px solid color-mix(in srgb, var(--border-color) 70%, transparent);
        }

        .pcs-collapse-table-collapse-text {
            color: var(--text-secondary) !important;
        }

        .pcs-table-other,
        .pcs-table-infobox {
            color: var(--text-primary) !important;
            font-weight: 600;
        }

        .pcs-collapse-table-content {
            background: var(--table-surface) !important;
        }

        .pcs-collapse-table-container table {
            margin: 0 !important;
            background: transparent !important;
        }

        /* Code */
        code, pre {
            font-family: 'SF Mono', Menlo, Consolas, monospace;
            font-size: 14px;
            background: var(--bg-subtle);
            border-radius: 4px;
        }

        code {
            padding: 2px 6px;
        }

        pre {
            padding: 16px;
            overflow-x: auto;
        }
        """

        let script = WKUserScript(
            source: """
            function appendToDocumentHead(node) {
                if (document.head) {
                    document.head.appendChild(node);
                } else if (document.documentElement) {
                    document.documentElement.appendChild(node);
                }
            }

            var style = document.createElement('style');
            style.textContent = `\(css)`;
            appendToDocumentHead(style);

            var meta = document.createElement('meta');
            meta.name = 'viewport';
            meta.content = 'width=device-width, initial-scale=1';
            appendToDocumentHead(meta);
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )

        webView.configuration.userContentController.addUserScript(script)

        let webViewScript = WKUserScript(
            source: WebViewResources.scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(webViewScript)


        // Register handlers
        Self.registerScriptMessageHandlers(on: webView, coordinator: context.coordinator)

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
        context.coordinator.readerAppearance = readerAppearance
        context.coordinator.readerTopInset = readerTopInset
        context.coordinator.preferImmediateReveal = preferImmediateReveal
        context.coordinator.onTableOfContentsUpdate = onTableOfContentsUpdate
        context.coordinator.onReferencesUpdate = onReferencesUpdate
        context.coordinator.onVisibleSectionChange = onVisibleSectionChange
        context.coordinator.onContentReveal = onContentReveal
        context.coordinator.onLinkHoverPreviewChange = onLinkHoverPreviewChange
        context.coordinator.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        context.coordinator.openTimer = openTimer
        context.coordinator.isSectionTrackingRequested =
            inspectorVisible && inspectorMode == .info
        context.coordinator.isReferencesRequested =
            inspectorVisible && inspectorMode == .references
        context.coordinator.syncLinkHoverPreviewOverlayState(
            isHovering: linkHoverPreviewOverlayHovering,
            presentedSignature: activeLinkHoverPreviewSignature
        )
        context.coordinator.syncNativeHighlightMenuMode(on: webView)

        // Process all pending actions (don't early-return so multiple can be handled)
        var didProcessPendingAction = false

        // Apply a color selected from the native highlight popover to the current WebView selection.
        if let pending = appState?.pendingImmediateHighlight {
            let script = "window.highlightCurrentSelection('\(pending.id.uuidString)', '\(pending.cssColor)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingImmediateHighlight = nil
            }
            context.coordinator.lastAppliedHighlightIds.insert(pending.id)
            didProcessPendingAction = true
        }

        // Apply pending highlight color change in WebView
        if let pending = appState?.pendingHighlightColorChange {
            let script = "window.updateHighlightColor('\(pending.id.uuidString)', '\(pending.cssColor)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingHighlightColorChange = nil
            }
            didProcessPendingAction = true
        }

        // Scroll to a specific highlight
        if let pending = appState?.pendingHighlightScroll {
            let script = "window.scrollToHighlight('\(pending.uuidString)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.pendingHighlightScroll = nil
            }
            didProcessPendingAction = true
        }

        // Scroll to a specific heading from Table of Contents
        if let sectionId = appState?.pendingTableOfContentsScrollTarget {
            let script = "window.scrollToSection('\(sectionId)');"
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.appState?.currentVisibleTableOfContentsSectionId = sectionId
                self.appState?.pendingTableOfContentsScrollTarget = nil
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
        if let pending = appState?.pendingHighlightRehydrate {
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
                            self.appState?.isHighlightRehydrateInProgress = false
                            self.appState?.lastHighlightRehydrateResult = AppState.HighlightRehydrateResult(
                                id: pending.id,
                                success: false,
                                timestamp: Date()
                            )
                        }
                        return
                    }

                    let success = result as? Bool ?? false
                    DispatchQueue.main.async {
                        self.appState?.isHighlightRehydrateInProgress = false
                        self.appState?.lastHighlightRehydrateResult = AppState.HighlightRehydrateResult(
                            id: pending.id,
                            success: success,
                            timestamp: Date()
                        )
                    }

                    guard success else { return }

                    if let target = context.coordinator.highlights.first(where: { $0.id == pending.id }) {
                        target.isStale = false
                        try? context.coordinator.modelContext?.save()
                    }
                }
            }

            DispatchQueue.main.async {
                self.appState?.pendingHighlightRehydrate = nil
            }
            return
        }

        // Only reload if document signature changed.
        let htmlSignature = Self.htmlReloadSignature(for: htmlContent)
        let shouldReloadContent =
            context.coordinator.lastLoadedArticleTitle != articleTitle ||
            context.coordinator.lastLoadedHTMLSignature != htmlSignature

        if shouldReloadContent {
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
            context.coordinator.lastAppliedReaderTopInset = -1
            context.coordinator.lastKnownHighlightsCount = highlights.count
            context.coordinator.lastHighlightDiffCheckTimestamp = 0
            context.coordinator.inspectorPublisher.resetForContentReload()
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
            context.coordinator.restoreScrollPositionIfNeeded(on: webView, desiredY: scrollPosition)
            context.coordinator.applyReaderAppearance(to: webView)
            context.coordinator.syncScrollTelemetryMode(on: webView)
            context.coordinator.syncRestoreTelemetryMode(on: webView)
            context.coordinator.maybeApplyHighlightsIfNeeded(to: webView, highlights: highlights)
            context.coordinator.refreshDeferredInspectorContentIfNeeded(on: webView)
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        coordinator.cleanup()
        // Remove message handlers to break retain cycle between userContentController and coordinator.
        unregisterScriptMessageHandlers(from: nsView)
        WebViewPool.shared.store(
            nsView,
            for: coordinator.tabID,
            lastLoadedArticleTitle: coordinator.lastLoadedArticleTitle,
            lastLoadedHTMLSignature: coordinator.lastLoadedHTMLSignature
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            tabID: tabID,
            onLinkTapped: onLinkTapped,
            scrollPosition: $scrollPosition,
            onScrollProgress: onScrollProgress,
            fallbackScrollProgress: fallbackScrollProgress,
            appState: appState,
            modelContext: modelContext,
            onTextSelected: onTextSelected,
            onSelectionCleared: onSelectionCleared,
            highlights: highlights,
            articleTitle: articleTitle,
            readerAppearance: readerAppearance,
            readerTopInset: readerTopInset,
            preferImmediateReveal: preferImmediateReveal,
            onTableOfContentsUpdate: onTableOfContentsUpdate,
            onReferencesUpdate: onReferencesUpdate,
            onVisibleSectionChange: onVisibleSectionChange,
            onContentReveal: onContentReveal,
            onLinkHoverPreviewChange: onLinkHoverPreviewChange,
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
        var highlightsApplied = false
        var lastAppliedHighlightIds: Set<UUID> = []
        var readerAppearance: ReaderAppearance
        var readerTopInset: CGFloat
        var preferImmediateReveal: Bool
        var onTableOfContentsUpdate: (([ArticleTableOfContentsItem]) -> Void)?
        var onReferencesUpdate: (([ArticleReferenceSection]) -> Void)?
        var onVisibleSectionChange: ((String?) -> Void)?
        var onContentReveal: (() -> Void)?
        var onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?
        var nativeHighlightingMenuEnabled: Bool
        var openTimer: Binding<ArticleOpenTimer>?
        var lastAppliedReaderAppearance: ReaderAppearance?
        var lastAppliedReaderTopInset: CGFloat = -1
        var lastAppliedNativeHighlightingMenuEnabled: Bool?
        var isSectionTrackingRequested: Bool = false
        var isReferencesRequested: Bool = false
        var lastAppliedSectionTrackingRequest: Bool?
        var lastAppliedRestoreTelemetryMode: Bool?
        weak var webView: WKWebView?
        var lastHighlightDiffCheckTimestamp: TimeInterval = 0
        var lastKnownHighlightsCount: Int = 0
        let inspectorPublisher = WebViewInspectorPublisher()
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
        var hasReportedContentReveal = false
        var pendingPostRevealTasks: [() -> Void] = []
        var lastSaveRequestTimestamp: TimeInterval = 0
        var lastScrollPositionPublishTimestamp: TimeInterval = 0
        var lastVisibleSectionPollTimestamp: TimeInterval = 0
        var lastHandledLinkSignature: String?
        var lastHandledLinkTimestamp: TimeInterval = 0
        var lastHandledAnyLinkTimestamp: TimeInterval = 0
        var adaptiveScrollDeltaThreshold: CGFloat = 14
        var adaptiveScrollTimeGate: TimeInterval = 0.9
        var adaptiveProgressDeltaThreshold: Double = 0.045
        var adaptiveProgressTimeGate: TimeInterval = 1.6
        var adaptiveSaveRequestInterval: TimeInterval = 3.4
        var adaptiveFallbackDeltaThreshold: CGFloat = 14
        var adaptiveFallbackTimeGate: TimeInterval = 1.4
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
            scrollPosition: Binding<CGFloat>,
            onScrollProgress: ((Double) -> Void)?,
            fallbackScrollProgress: Double?,
            appState: AppState?,
            modelContext: ModelContext?,
            onTextSelected: ((TextSelectionData) -> Void)?,
            onSelectionCleared: (() -> Void)?,
            highlights: [Highlight],
            articleTitle: String,
            readerAppearance: ReaderAppearance,
            readerTopInset: CGFloat,
            preferImmediateReveal: Bool,
            onTableOfContentsUpdate: (([ArticleTableOfContentsItem]) -> Void)?,
            onReferencesUpdate: (([ArticleReferenceSection]) -> Void)?,
            onVisibleSectionChange: ((String?) -> Void)?,
            onContentReveal: (() -> Void)?,
            onLinkHoverPreviewChange: ((WebViewLinkHoverRequest?) -> Void)?,
            nativeHighlightingMenuEnabled: Bool
        ) {
            self.tabID = tabID
            self.onLinkTapped = onLinkTapped
            self.scrollPosition = scrollPosition
            self.onScrollProgress = onScrollProgress
            self.fallbackScrollProgress = fallbackScrollProgress
            self.appState = appState
            self.modelContext = modelContext
            self.onTextSelected = onTextSelected
            self.onSelectionCleared = onSelectionCleared
            self.highlights = highlights
            self.articleTitle = articleTitle
            self.readerAppearance = readerAppearance
            self.readerTopInset = readerTopInset
            self.preferImmediateReveal = preferImmediateReveal
            self.onTableOfContentsUpdate = onTableOfContentsUpdate
            self.onReferencesUpdate = onReferencesUpdate
            self.onVisibleSectionChange = onVisibleSectionChange
            self.onContentReveal = onContentReveal
            self.onLinkHoverPreviewChange = onLinkHoverPreviewChange
            self.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        }

        func attachReusedWebView(_ webView: WKWebView) {
            dismissLinkHoverPreview(immediate: true)
            cancelScriptedScrollRestore(on: webView)
            isContentLoadInFlight = false
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            self.webView = webView
            setupScrollObserver(for: webView)
            syncScrollTelemetryMode(on: webView, force: true)
            syncRestoreTelemetryMode(on: webView, force: true)
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

            // Allow invalid schemes to fail gracefully or be handled by system
            if url.scheme == "about" || url.scheme == "data" {
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

            // 2. Handle External Links (http/https) that are NOT wiki links
            // If we got here, it's not a /wiki/ link.
            if url.scheme == "http" || url.scheme == "https" {
                // Determine if it's the initial page load or a user click
                // Initial load: navigationType is .other and request matches main frame
                // User click: .linkActivated

                if navigationAction.navigationType == .linkActivated || navigationAction.targetFrame == nil {
                    // It's a user action -> Open in Browser
                    _ = SystemBridge.openURLExternally(url)
                    decisionHandler(.cancel)
                    return
                }
            }

            // 3. Allow everything else
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            // Route target="_blank" requests back through the normal navigation policy.
            if navigationAction.request.url != nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        var scrollObserver: NSObjectProtocol?

        func cleanup() {
            findRequestTimeoutWorkItem?.cancel()
            findRequestTimeoutWorkItem = nil
            dismissLinkHoverPreview(immediate: true)
            if let observer = scrollObserver {
                NotificationCenter.default.removeObserver(observer)
                scrollObserver = nil
            }
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
                let desiredFetchPriority = shouldBeEager ? "high" : "low"
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
        self.articleTitle = articleTitle
        self.baseURL = baseURL
        self.onLinkTapped = onLinkTapped
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

private enum WebViewResources {
    static let scriptSource: String = {
        guard let url = resolvedScriptURL(),
              let data = try? Data(contentsOf: url),
              let script = String(data: data, encoding: .utf8) else {
            assertionFailure("Missing WebView.js in bundle")
            return ""
        }
        return script
    }()

    private static func resolvedScriptURL() -> URL? {
        if let directMainURL = Bundle.main.url(forResource: "WebView", withExtension: "js") {
            return directMainURL
        }

        if let moduleSubdirectoryURL = Bundle.main.url(
            forResource: "WebView",
            withExtension: "js",
            subdirectory: "MacWiki_MacWiki.bundle"
        ) {
            return moduleSubdirectoryURL
        }

        return Bundle.module.url(forResource: "WebView", withExtension: "js")
    }
}

enum ScrollProfile {
    case responsive
    case balanced
    case economy
}
