import SwiftUI
import AppKit
import WebKit
import SwiftData

private enum ReaderChromeMetrics {
    static let defaultTopInset: CGFloat = 56
}

/// Data passed from JavaScript when text is selected
struct TextSelectionData: Equatable {
    let text: String
    let elementPath: String
    let startOffset: Int
    let length: Int
    let contextBefore: String
    let contextAfter: String
    let sectionTitle: String?
    let rect: CGRect  // Position for toolbar
}

/// Data for link action requests coming from WebView right-click events.
struct WebViewLinkContextRequest: Equatable {
    let url: URL
    let articleTitle: String?
    let point: CGPoint
}

/// Data for highlight action requests coming from WebView right-click events.
struct WebViewHighlightContextRequest: Equatable {
    let id: UUID
    let point: CGPoint
}

/// Data for selected text right-click actions coming from WebView.
struct WebViewSelectionContextRequest: Equatable {
    let selection: TextSelectionData
    let point: CGPoint
}

/// Data for link hover preview requests coming from WebView hover events.
struct WebViewLinkHoverRequest: Equatable, Sendable {
    let url: URL
    let articleTitle: String?
    let point: CGPoint
}

private enum LinkHoverPreviewMetrics {
    static let width: CGFloat = 476
    static let height: CGFloat = 364
}

private enum LinkHoverGlassMetrics {
    static let cornerRadius: CGFloat = 20
    static let borderWidth: CGFloat = 0.7
    static let contentInset: CGFloat = 10
}

private enum LinkHoverSummaryPreviewMetrics {
    static let maxExtractCharacters = 360
    static let artworkHeight: CGFloat = 152
}

private struct LinkHoverPreviewPane: View {
    @Environment(\.colorScheme) private var colorScheme

    let title: String
    let url: URL
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onSave: () -> Void
    var onHoverStateChange: (Bool) -> Void = { _ in }

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            LinkHoverArticleSummaryPreview(articleTitle: title, fallbackURL: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(glassPlane)
        .clipShape(RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous))
        .overlay(glassBorder)
        .shadow(
            color: .black.opacity(isDarkMode ? 0.34 : 0.16),
            radius: 20,
            y: 12
        )
        .padding(LinkHoverGlassMetrics.contentInset)
        .frame(width: LinkHoverPreviewMetrics.width, height: LinkHoverPreviewMetrics.height)
        .background(Color.clear)
        .contentShape(RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous))
        .onHover(perform: onHoverStateChange)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.primary)
                .layoutPriority(1)

            HStack(spacing: 8) {
                Spacer(minLength: 0)

                LinkHoverActionIcon(
                    systemImage: "arrow.up.forward",
                    helpText: "Open",
                    action: onOpen
                )

                LinkHoverActionIcon(
                    systemImage: "plus.square.on.square",
                    helpText: "Open in New Tab",
                    action: onOpenInNewTab
                )

                LinkHoverActionIcon(
                    systemImage: "bookmark",
                    helpText: "Save Link",
                    action: onSave
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(isDarkMode ? 0.18 : 0.08))
                .frame(height: 0.6)
        }
    }

    private var glassPlane: some View {
        RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(isDarkMode ? 0.20 : 0.08))
            }
            .overlay(
                RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDarkMode ? 0.16 : 0.28),
                                Color.white.opacity(isDarkMode ? 0.05 : 0.12),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(isDarkMode ? 0.28 : 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.multiply)
            )
    }

    private var glassBorder: some View {
        RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isDarkMode ? 0.32 : 0.44),
                        Color.white.opacity(isDarkMode ? 0.07 : 0.18)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: LinkHoverGlassMetrics.borderWidth
            )
            .overlay {
                RoundedRectangle(cornerRadius: LinkHoverGlassMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isDarkMode ? 0.16 : 0.08),
                        lineWidth: 0.45
                    )
            }
    }
}

private struct LinkHoverActionIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    let systemImage: String
    let helpText: String
    let action: () -> Void

    private var isDarkMode: Bool {
        colorScheme == .dark
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13.5, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(isHovered ? Color.accentColor : .primary)
                .background(iconBackground)
                .scaleEffect(isHovered ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(helpText)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    private var iconBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovered ? (isDarkMode ? 0.18 : 0.12) : 0))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isDarkMode ? 0.07 : 0.22),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(isDarkMode ? 0.20 : 0.32),
                        lineWidth: 0.6
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isHovered ? (isDarkMode ? 0.24 : 0.16) : (isDarkMode ? 0.14 : 0.08)),
                        lineWidth: 0.5
                    )
            }
            .shadow(
                color: .black.opacity(isDarkMode ? 0.30 : 0.12),
                radius: 4,
                y: 2
            )
    }
}

private struct LinkHoverArticleSummaryPreview: View {
    let articleTitle: String
    let fallbackURL: URL

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var descriptionText: String?
    @State private var extractText: String?
    @State private var thumbnailURL: URL?
    @State private var summaryTitle: String?
    @State private var isLoading = false
    @State private var hasLoaded = false

    private enum PresentationState {
        case loading
        case content
        case unavailable
    }

    private var hasContent: Bool {
        descriptionText != nil || extractText != nil || thumbnailURL != nil
    }

    private var hasTextualSummary: Bool {
        descriptionText != nil || extractText != nil
    }

    private var requestKey: String {
        let normalizedTitle = articleTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        if normalizedTitle.isEmpty {
            return fallbackURL.absoluteString
        }
        return normalizedTitle
    }

    private var thumbnailTransaction: Transaction {
        reduceMotion ? Transaction(animation: nil) : Transaction(animation: .easeOut(duration: 0.18))
    }

    private var artworkMonogram: String {
        let source = (summaryTitle ?? articleTitle)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let character = source.first else { return "W" }
        return String(character).uppercased()
    }

    private var presentationState: PresentationState {
        if isLoading {
            return .loading
        }
        if hasContent {
            return .content
        }
        if hasLoaded {
            return .unavailable
        }
        return .loading
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            currentStateView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: presentationState)
        .task(id: requestKey) {
            await loadSummary()
        }
    }

    @ViewBuilder
    private var currentStateView: some View {
        switch presentationState {
        case .loading:
            loadingStateView
                .transition(.opacity)
        case .content:
            contentView
                .transition(.opacity)
        case .unavailable:
            unavailableStateView
                .transition(.opacity)
        }
    }

    private var contentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            previewArtwork

            if let descriptionText {
                Text(descriptionText)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineLimit(2)
            }

            if let extractText {
                Text(extractText)
                    .font(.system(size: 13.5))
                    .lineSpacing(3)
                    .foregroundStyle(.primary.opacity(0.92))
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !hasTextualSummary {
                Text("A visual preview is available for this link.")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary.opacity(0.82))
                    .lineSpacing(2)
            }
        }
    }

    private var loadingStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            loadingArtwork

            AppLoadingInlineLabel(
                text: "Loading preview...",
                tone: .neutral,
                font: .caption.weight(.medium)
            )

            VStack(alignment: .leading, spacing: 8) {
                AppLoadingSkeletonBar(width: 140, height: 10, cornerRadius: 5, tone: .neutral)
                AppLoadingSkeletonBar(width: nil, height: 12, cornerRadius: 6, tone: .neutral)
                AppLoadingSkeletonBar(width: nil, height: 12, cornerRadius: 6, tone: .neutral)
                AppLoadingSkeletonBar(width: 208, height: 12, cornerRadius: 6, tone: .neutral)
            }
        }
    }

    private var unavailableStateView: some View {
        VStack(alignment: .leading, spacing: 12) {
            fallbackArtwork

            Text("Summary unavailable")
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("A clean preview was not available for this link right now.")
                .font(.system(size: 13))
                .foregroundStyle(.primary.opacity(0.8))
                .lineSpacing(2)
        }
    }

    private var previewArtwork: some View {
        Group {
            if let thumbnailURL {
                AsyncImage(url: thumbnailURL, transaction: thumbnailTransaction) { phase in
                    switch phase {
                    case .empty:
                        loadingArtwork
                    case .success(let image):
                        ZStack {
                            artworkBackground
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .transition(.opacity)
                        }
                    case .failure:
                        fallbackArtwork
                    @unknown default:
                        fallbackArtwork
                    }
                }
            } else {
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: LinkHoverSummaryPreviewMetrics.artworkHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.28), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 6)
    }

    private var fallbackArtwork: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(colorScheme == .dark ? 0.70 : 0.60),
                    Color.blue.opacity(colorScheme == .dark ? 0.58 : 0.48),
                    Color.primary.opacity(colorScheme == .dark ? 0.24 : 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.14))
                .frame(width: 120, height: 120)
                .blur(radius: 14)
                .offset(x: 36, y: -40)

            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)

                Text(artworkMonogram)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(14)
        }
    }

    private var loadingArtwork: some View {
        ZStack {
            AppLoadingSkeletonBar(
                width: nil,
                height: LinkHoverSummaryPreviewMetrics.artworkHeight,
                cornerRadius: 12,
                tone: .accent
            )

            Image(systemName: "globe.americas.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: LinkHoverSummaryPreviewMetrics.artworkHeight)
    }

    private var artworkBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.06 : 0.18),
                        Color.clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.12 : 0.04))
            }
    }

    @MainActor
    private func loadSummary() async {
        isLoading = true
        hasLoaded = false
        summaryTitle = nil
        thumbnailURL = nil
        descriptionText = nil
        extractText = nil

        let trimmedTitle = articleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            isLoading = false
            hasLoaded = true
            return
        }

        do {
            let summary = try await WikipediaService.shared.fetchSummary(trimmedTitle)
            guard !Task.isCancelled else { return }

            summaryTitle = normalize(summary.title)
            let normalizedDescription = normalize(summary.description)
            let normalizedExtract = normalize(summary.extract)
            thumbnailURL = summary.thumbnailURL
            descriptionText = normalizedDescription
            if let normalizedExtract {
                extractText = truncatedPreviewText(
                    normalizedExtract,
                    maxCharacters: LinkHoverSummaryPreviewMetrics.maxExtractCharacters
                )
            }
        } catch {
            guard !Task.isCancelled else { return }
        }

        isLoading = false
        hasLoaded = true
    }

    private func normalize(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? nil : collapsed
    }

    private func truncatedPreviewText(_ text: String, maxCharacters: Int) -> String {
        guard text.count > maxCharacters else { return text }
        let capped = String(text.prefix(maxCharacters))
        if let punctuationIndex = capped.lastIndex(where: { ".!?".contains($0) }),
           capped.distance(from: capped.startIndex, to: punctuationIndex) >= 140 {
            return String(capped[...punctuationIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return capped.trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
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
    var readerTopInset: CGFloat = ReaderChromeMetrics.defaultTopInset

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
    var focusModeEnabled: Bool = false
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
        "scrollPerfSnapshot"
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
        context.coordinator.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        context.coordinator.openTimer = openTimer
        context.coordinator.isSectionTrackingRequested =
            (inspectorVisible && inspectorMode == .info) || focusModeEnabled
        context.coordinator.syncNativeHighlightMenuMode(on: webView)

        // Process all pending actions (don't early-return so multiple can be handled)
        var didProcessPendingAction = false

        // Check for pending immediate highlight (user just clicked a color)
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
            let preparedHTMLContent = context.coordinator.prepareHTMLForInitialLoad(htmlContent)
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
            context.coordinator.lastTOCPublishedForTitle = ""
            context.coordinator.lastReferencesPublishedForTitle = ""
            context.coordinator.resetPublishedTOCFingerprint()
            context.coordinator.resetPublishedReferencesFingerprint()
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

            // Republish TOC and visible section on tab switch so inspector updates.
            // Guard: only re-publish when article title changed (tab switch), not every state update.
            if context.coordinator.lastTOCPublishedForTitle != articleTitle {
                context.coordinator.lastTOCPublishedForTitle = articleTitle
                context.coordinator.resetPublishedTOCFingerprint()
                context.coordinator.publishTableOfContents(from: webView)
                context.coordinator.publishVisibleSection(from: webView, force: true)
            }

            if context.coordinator.lastReferencesPublishedForTitle != articleTitle {
                context.coordinator.lastReferencesPublishedForTitle = articleTitle
                context.coordinator.resetPublishedReferencesFingerprint()
                context.coordinator.publishReferences(from: webView)
            }
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

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, NSPopoverDelegate {
        let tabID: UUID
        var onLinkTapped: ((String) -> Void)?
        var onTextSelected: ((TextSelectionData) -> Void)?
        var onSelectionCleared: (() -> Void)?
        var scrollPosition: Binding<CGFloat>
        var onScrollProgress: ((Double) -> Void)?
        var fallbackScrollProgress: Double?
        var lastLoadedArticleTitle: String = ""
        var lastLoadedHTMLSignature: UInt64 = 0
        private var recoveryHTMLPayload: String?
        private var recoveryBaseURL: URL?
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
        var nativeHighlightingMenuEnabled: Bool
        var openTimer: Binding<ArticleOpenTimer>?
        var lastAppliedReaderAppearance: ReaderAppearance?
        var lastAppliedReaderTopInset: CGFloat = -1
        var lastAppliedNativeHighlightingMenuEnabled: Bool?
        var isSectionTrackingRequested: Bool = false
        var lastAppliedSectionTrackingRequest: Bool?
        var lastAppliedRestoreTelemetryMode: Bool?
        weak var webView: WKWebView?
        var lastHighlightDiffCheckTimestamp: TimeInterval = 0
        var lastKnownHighlightsCount: Int = 0
        private var lastReportedProgress: Double = -1
        private var lastProgressTimestamp: TimeInterval = 0
        private var lastReportedVisibleSectionId: String?
        private var hasTableOfContents = false
        var lastTOCPublishedForTitle: String = ""
        var lastReferencesPublishedForTitle: String = ""
        private var lastPublishedTOCFingerprint: Int?
        private var lastPublishedReferencesFingerprint: Int?
        private var hasPublishedNonEmptyTOCSinceLoad = false
        private var hasPublishedNonEmptyReferencesSinceLoad = false
        private var isTOCPublishInFlight = false
        private var isReferencesPublishInFlight = false
        private var lastKnownScrollY: CGFloat = 0
        private var highVelocityUserScrollUntil: TimeInterval = 0
        private var lastProgrammaticScrollTimestamp: TimeInterval = 0
        private var programmaticScrollActiveUntil: TimeInterval = 0
        private var hasProgrammaticScrollInFlight = false
        private var lastJSTelemetryTimestamp: TimeInterval = 0
        private var suppressInitialScrollPersistenceUntil: TimeInterval = 0
        private var hasPendingNonZeroRestore = false
        private var pendingNonZeroRestoreDeadline: TimeInterval = 0
        private var pendingRestoreUnlockProgress: Double = 0.08
        private var pendingRestoreUnlockY: CGFloat = 80
        private var hasUserDrivenScrollSinceLoad = false
        private var isContentLoadInFlight = false
        private var expectedNavigationToken: ObjectIdentifier?
        private var activeRestoreSessionID: UUID?
        private var webContentTerminationCount = 0
        private var hasReportedContentReveal = false
        private var pendingPostRevealTasks: [() -> Void] = []
        private var lastSaveRequestTimestamp: TimeInterval = 0
        private var lastScrollPositionPublishTimestamp: TimeInterval = 0
        private var lastVisibleSectionPollTimestamp: TimeInterval = 0
        private var lastHandledLinkSignature: String?
        private var lastHandledLinkTimestamp: TimeInterval = 0
        private var lastHandledAnyLinkTimestamp: TimeInterval = 0
        private var adaptiveScrollDeltaThreshold: CGFloat = 14
        private var adaptiveScrollTimeGate: TimeInterval = 0.9
        private var adaptiveProgressDeltaThreshold: Double = 0.045
        private var adaptiveProgressTimeGate: TimeInterval = 1.6
        private var adaptiveSaveRequestInterval: TimeInterval = 3.4
        private var adaptiveFallbackDeltaThreshold: CGFloat = 14
        private var adaptiveFallbackTimeGate: TimeInterval = 1.4
        private var currentScrollProfile: ScrollProfile = .balanced
        private var isFindRequestInFlight = false
        private var activeFindRequestID: UUID?
        private var queuedFindRequest: AppState.FindOnPageRequest?
        private var findRequestTimeoutWorkItem: DispatchWorkItem?
        private var linkHoverPopover: NSPopover?
        private var linkHoverHostingController: NSHostingController<LinkHoverPreviewPane>?
        private var pendingLinkHoverHideWorkItem: DispatchWorkItem?
        private var activeLinkHoverSignature: String?
        private var isHoveringLinkPreviewSource = false
        private var isHoveringLinkPreviewPopover = false
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

        private enum LinkMenuAction {
            case open
            case openInNewTab
            case openInNewBackgroundTab
            case copyTitle
            case copyLink
            case saveToList
        }

        private final class LinkMenuPayload: NSObject {
            let action: LinkMenuAction
            let url: URL
            let articleTitle: String?
            let readingListID: UUID?

            init(
                action: LinkMenuAction,
                url: URL,
                articleTitle: String?,
                readingListID: UUID? = nil
            ) {
                self.action = action
                self.url = url
                self.articleTitle = articleTitle
                self.readingListID = readingListID
            }
        }

        private enum HighlightMenuAction {
            case setColor(HighlightColor)
            case editNote
            case delete
        }

        private final class HighlightMenuPayload: NSObject {
            let action: HighlightMenuAction
            let highlightID: UUID

            init(action: HighlightMenuAction, highlightID: UUID) {
                self.action = action
                self.highlightID = highlightID
            }
        }

        private enum SelectionMenuAction {
            case highlight(HighlightColor)
            case highlightWithNote(HighlightColor)
            case copySelection
        }

        private final class SelectionMenuPayload: NSObject {
            let action: SelectionMenuAction
            let request: WebViewSelectionContextRequest

            init(action: SelectionMenuAction, request: WebViewSelectionContextRequest) {
                self.action = action
                self.request = request
            }
        }

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
            self.nativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
        }

        func attachReusedWebView(_ webView: WKWebView) {
            dismissLinkHoverPreview(immediate: true)
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

        private func handleScriptMessage(name: String, body: Any) {
            switch name {
            case "linkClicked":
                if let urlString = body as? String {
                    handleLinkClick(urlString)
                } else if let data = body as? [String: Any],
                          let urlString = data["url"] as? String {
                    // Command-click should open in a background tab (keep current tab active).
                    let optionClick = data["altKey"] as? Bool ?? false
                    let commandClick = (data["metaKey"] as? Bool ?? false) && !optionClick
                    handleLinkClick(
                        urlString,
                        openInNewTab: commandClick,
                        activateNewTab: !commandClick,
                        optionClick: optionClick
                    )
                }

            case "linkRightClicked":
                if let data = body as? [String: Any] {
                    handleLinkContextRequest(data)
                }

            case "linkHoverChanged":
                if let data = body as? [String: Any] {
                    handleLinkHoverRequest(data)
                }

            case "textSelected":
                if let data = body as? [String: Any] {
                    handleTextSelection(data)
                }

            case "selectionCleared":
                onSelectionCleared?()

            case "textSelectionContextRequested":
                if let data = body as? [String: Any] {
                    handleSelectionContextRequest(data)
                }

            case "scrollChanged":
                if let data = body as? [String: Any] {
                    handleScrollChanged(data)
                }

            case "scrollPerfSnapshot":
                if let data = body as? [String: Any] {
                    handleScrollPerfSnapshot(data)
                }

            case "highlightShortcut":
                if let data = body as? [String: Any],
                   let text = data["text"] as? String {
                    // Trigger highlight creation with default color
                    appState?.pendingHighlightText = text
                }

            case "highlightClicked":
                if let data = body as? [String: Any],
                   let idString = data["id"] as? String {
                    appState?.selectedHighlightId = idString
                    appState?.inspectorMode = .notes
                    appState?.inspectorVisible = true
                }

            case "highlightResult":
                if let data = body as? [String: Any],
                   data["total"] as? Int != nil,
                   data["success"] as? Int != nil {
                    if let failedIds = data["failedIds"] as? [String] {
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
                }
                
            case "highlightRightClicked":
                if let data = body as? [String: Any] {
                    handleHighlightContextRequest(data)
                }

            case "referenceClicked":
                if let data = body as? [String: Any],
                   let referenceId = data["referenceId"] as? String {
                    appState?.selectedReferenceId = normalizedReferenceIdentifier(referenceId)
                    appState?.inspectorMode = .references
                    appState?.inspectorVisible = true
                }

            default:
                break
            }
        }

        private func handleTextSelection(_ data: [String: Any]) {
            guard let selectionData = parseTextSelectionData(from: data) else { return }
            onTextSelected?(selectionData)
        }

        private func handleSelectionContextRequest(_ data: [String: Any]) {
            guard let selectionData = parseTextSelectionData(from: data) else { return }
            let request = WebViewSelectionContextRequest(
                selection: selectionData,
                point: contextPoint(from: data)
            )
            presentNativeSelectionContextMenu(for: request)
        }

        private func parseTextSelectionData(from data: [String: Any]) -> TextSelectionData? {
            guard let text = data["text"] as? String,
                  let elementPath = data["elementPath"] as? String,
                  let startOffset = data["startOffset"] as? Int,
                  let length = data["length"] as? Int,
                  let rectData = data["rect"] as? [String: Any],
                  let x = numericValue(from: rectData["x"]),
                  let y = numericValue(from: rectData["y"]),
                  let width = numericValue(from: rectData["width"]),
                  let height = numericValue(from: rectData["height"])
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

        private func normalizedReferenceIdentifier(_ rawIdentifier: String) -> String {
            rawIdentifier.removingPercentEncoding ?? rawIdentifier
        }

        private func handleScrollChanged(_ data: [String: Any]) {
            if isContentLoadInFlight {
                return
            }
            let now = Date().timeIntervalSinceReferenceDate
            let userInitiated = data["userInitiated"] as? Bool ?? false
            let isProgrammaticEvent = data["programmatic"] as? Bool ?? false
            let hadProgrammaticInFlight = hasProgrammaticScrollInFlight
            let y = (data["y"] as? Double).map { CGFloat($0) } ?? 0
            let progress = data["progress"] as? Double
            let velocity = max(data["velocity"] as? Double ?? 0, 0)
            let gestureFast = data["gestureFast"] as? Bool ?? false
            let burstHeartbeat = data["burstHeartbeat"] as? Bool ?? false
            let directionChanged = data["directionChanged"] as? Bool ?? false
            lastJSTelemetryTimestamp = now

            if isProgrammaticEvent {
                hasProgrammaticScrollInFlight = true
                markProgrammaticScroll(y: y, activeFor: 0.72)
            } else if hadProgrammaticInFlight {
                hasProgrammaticScrollInFlight = false
                programmaticScrollActiveUntil = max(programmaticScrollActiveUntil, now + 0.16)
            }

            if userInitiated {
                noteUserDrivenScroll(now: now)
                if !isProgrammaticEvent && (velocity > 0.52 || gestureFast || burstHeartbeat) {
                    var window: TimeInterval
                    if burstHeartbeat {
                        window = 0.66
                    } else {
                        window = gestureFast ? 0.46 : 0.34
                    }
                    if directionChanged {
                        window = min(window, 0.24)
                    }
                    highVelocityUserScrollUntil = max(highVelocityUserScrollUntil, now + window)
                }
                if directionChanged {
                    highVelocityUserScrollUntil = min(
                        max(highVelocityUserScrollUntil, now + 0.12),
                        now + 0.24
                    )
                }
            }

            lastKnownScrollY = y
            if shouldIgnoreInitialTopTelemetry(y: y, progress: progress, now: now) {
                return
            }
            if burstHeartbeat {
                return
            }
            let inHighVelocityWindow =
                !isProgrammaticEvent &&
                now < highVelocityUserScrollUntil
            let delta = abs(scrollPosition.wrappedValue - y)
            let dynamicScrollDeltaThreshold =
                inHighVelocityWindow
                ? max(adaptiveScrollDeltaThreshold, directionChanged ? 22 : 40)
                : adaptiveScrollDeltaThreshold
            let dynamicScrollTimeGate =
                inHighVelocityWindow
                ? (
                    directionChanged
                    ? min(adaptiveScrollTimeGate, 0.72)
                    : max(adaptiveScrollTimeGate, 1.25)
                )
                : adaptiveScrollTimeGate
            let dynamicMinorDeltaGate: CGFloat
            if inHighVelocityWindow {
                if directionChanged {
                    dynamicMinorDeltaGate = gestureFast ? 12 : 8
                } else {
                    dynamicMinorDeltaGate = gestureFast ? 24 : 18
                }
            } else {
                dynamicMinorDeltaGate = 3
            }
            let shouldPublishScrollPosition =
                delta > dynamicScrollDeltaThreshold ||
                ((now - lastScrollPositionPublishTimestamp) > dynamicScrollTimeGate && delta > dynamicMinorDeltaGate)
            let didEndProgrammaticBurst = !isProgrammaticEvent && hadProgrammaticInFlight
            let shouldSuppressProgrammaticSideEffects =
                !didEndProgrammaticBurst && isProgrammaticScrollActive(now: now)
            let shouldCommitScrollPosition =
                shouldPublishScrollPosition &&
                (!shouldSuppressProgrammaticSideEffects || didEndProgrammaticBurst)

            if shouldCommitScrollPosition {
                scrollPosition.wrappedValue = y
                lastScrollPositionPublishTimestamp = now
                if !shouldSuppressProgrammaticSideEffects {
                    requestSaveIfNeeded(force: didEndProgrammaticBurst)
                }
            }

            if let progress, !shouldSuppressProgrammaticSideEffects {
                if inHighVelocityWindow && !didEndProgrammaticBurst {
                    let minProgressInterval: TimeInterval
                    if directionChanged {
                        minProgressInterval = gestureFast
                            ? min(adaptiveProgressTimeGate, 0.95)
                            : min(adaptiveProgressTimeGate, 0.85)
                    } else {
                        minProgressInterval = gestureFast
                            ? max(adaptiveProgressTimeGate, 1.55)
                            : max(adaptiveProgressTimeGate, 1.35)
                    }
                    if (now - lastProgressTimestamp) >= minProgressInterval {
                        reportScrollProgressValue(progress)
                    }
                } else {
                    reportScrollProgressValue(progress, force: didEndProgrammaticBurst)
                }
            }

            // Read sectionId directly from JS telemetry (computed synchronously
            // via cached heading positions + binary search — no async round-trip).
            let shouldTrackVisibleSection =
                hasTableOfContents && isSectionTrackingRequested
            if !shouldSuppressProgrammaticSideEffects,
               shouldTrackVisibleSection,
               let sectionId = data["sectionId"] as? String {
                if sectionId != lastReportedVisibleSectionId {
                    lastReportedVisibleSectionId = sectionId
                    onVisibleSectionChange?(sectionId)
                }
            }
        }

        private func handleScrollPerfSnapshot(_ data: [String: Any]) {
            let longTasks = data["longTasks"] as? Int ?? 0
            let avgVelocity = data["avgVelocity"] as? Double ?? 0
            let postsPerSecond = data["postsPerSecond"] as? Double ?? 0

            let targetProfile: ScrollProfile
            if longTasks >= 2 {
                targetProfile = .economy
            } else if avgVelocity < 0.45 && postsPerSecond < 8.0 {
                targetProfile = .responsive
            } else {
                targetProfile = .balanced
            }

            applyScrollProfile(targetProfile)
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
        
        private func handleLinkClick(
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
            
            // Handle external links
            if url.scheme == "http" || url.scheme == "https" {
                DispatchQueue.main.async {
                    _ = SystemBridge.openURLExternally(url)
                }
            }
        }

        private func shouldHandleLink(url: URL, newTab: Bool, optionSave: Bool = false) -> Bool {
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

            // Longer de-dupe window absorbs link event storms while preserving normal navigation.
            let isDuplicate = signature == lastHandledLinkSignature && (now - lastHandledLinkTimestamp) < 0.9
            if isDuplicate {
                return false
            }
            lastHandledLinkSignature = signature
            lastHandledLinkTimestamp = now
            lastHandledAnyLinkTimestamp = now
            return true
        }

        private struct WikipediaLinkTarget {
            let id: String
            let displayTitle: String
        }

        private func wikipediaLinkTarget(from url: URL) -> WikipediaLinkTarget? {
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

        private func wikipediaRawTitle(fromPath path: String) -> String? {
            guard let range = path.range(of: "/wiki/", options: .backwards) else {
                return nil
            }
            let rawTitle = String(path[range.upperBound...])
            return rawTitle.isEmpty ? nil : rawTitle
        }

        private func wikipediaIndexPath(_ path: String) -> Bool {
            let lowered = path.lowercased()
            return lowered == "/w/index.php" ||
                lowered.hasSuffix("/w/index.php") ||
                lowered == "/wiki/index.php" ||
                lowered.hasSuffix("/wiki/index.php")
        }

        private func shouldTreatIndexRouteAsArticle(using components: URLComponents) -> Bool {
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

        private func queryItemValue(named name: String, in components: URLComponents) -> String? {
            components.queryItems?
                .first { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }?
                .value
        }

        private func wikipediaLinkTarget(rawTitle: String) -> WikipediaLinkTarget? {
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

        private func normalizedArticleKey(_ title: String) -> String {
            title
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
        }

        private func scrollToAnchor(_ fragment: String) {
            guard let webView else { return }
            let escapedFragment = fragment
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "")
            let script = "window.scrollToAnchor && window.scrollToAnchor('\(escapedFragment)');"
            webView.evaluateJavaScript(script)
        }

        private func handleLinkHoverRequest(_ data: [String: Any]) {
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
                url: url,
                articleTitle: hoverTitle,
                point: contextPoint(from: data)
            )
            presentLinkHoverPreview(for: request)
        }

        private func hoverPreviewTitle(from data: [String: Any], url: URL) -> String? {
            if let raw = data["articleTitle"] as? String {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
            return articleTitle(from: url)
        }

        private func shouldPresentHoverPreview(for url: URL, previewTitle: String?) -> Bool {
            guard let target = wikipediaLinkTarget(from: url) else { return false }
            let resolvedTitle = (previewTitle?.trimmingCharacters(in: .whitespacesAndNewlines))
                .flatMap { $0.isEmpty ? nil : $0 } ?? target.displayTitle
            return normalizedArticleKey(resolvedTitle) != normalizedArticleKey(articleTitle)
        }

        private func presentLinkHoverPreview(for request: WebViewLinkHoverRequest) {
            guard let webView else { return }

            pendingLinkHoverHideWorkItem?.cancel()
            pendingLinkHoverHideWorkItem = nil

            let signature = linkHoverSignature(for: request.url)
            let displayTitle = request.articleTitle ?? articleTitle(from: request.url) ?? "Article"
            if activeLinkHoverSignature == signature, linkHoverPopover?.isShown == true {
                return
            }

            activeLinkHoverSignature = signature
            let pane = LinkHoverPreviewPane(
                title: displayTitle,
                url: request.url,
                onOpen: { [weak self] in
                    self?.openLinkFromContextMenu(request.url, inNewTab: false)
                },
                onOpenInNewTab: { [weak self] in
                    self?.openLinkFromContextMenu(request.url, inNewTab: true)
                },
                onSave: { [weak self] in
                    self?.saveLinkFromHoverPreview(request.url)
                },
                onHoverStateChange: { [weak self] hovering in
                    self?.handleLinkHoverPreviewHoverChanged(hovering)
                }
            )
            showLinkHoverPopover(with: pane, at: request.point, in: webView)
        }

        private func linkHoverSignature(for url: URL) -> String {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.fragment = nil
            return components?.string ?? url.absoluteString
        }

        private func showLinkHoverPopover(
            with pane: LinkHoverPreviewPane,
            at point: CGPoint,
            in webView: WKWebView
        ) {
            let popover: NSPopover
            if let existing = linkHoverPopover {
                popover = existing
            } else {
                let created = NSPopover()
                created.behavior = .applicationDefined
                created.animates = true
                created.delegate = self
                linkHoverPopover = created
                popover = created
            }

            if let controller = linkHoverHostingController {
                controller.rootView = pane
            } else {
                let controller = NSHostingController(rootView: pane)
                linkHoverHostingController = controller
                popover.contentViewController = controller
            }
            popover.contentViewController = linkHoverHostingController
            popover.contentSize = NSSize(width: LinkHoverPreviewMetrics.width, height: LinkHoverPreviewMetrics.height)
            isHoveringLinkPreviewPopover = false

            let anchorPoint = contextMenuPoint(point, in: webView)
            let anchorRect = NSRect(x: anchorPoint.x, y: anchorPoint.y, width: 1, height: 1)
            if popover.isShown {
                popover.performClose(nil)
            }
            popover.show(relativeTo: anchorRect, of: webView, preferredEdge: .maxY)
        }

        private func handleLinkHoverPreviewHoverChanged(_ hovering: Bool) {
            isHoveringLinkPreviewPopover = hovering
            if hovering {
                pendingLinkHoverHideWorkItem?.cancel()
                pendingLinkHoverHideWorkItem = nil
            } else if !isHoveringLinkPreviewSource {
                dismissLinkHoverPreview(immediate: false)
            }
        }

        private func dismissLinkHoverPreview(immediate: Bool) {
            pendingLinkHoverHideWorkItem?.cancel()
            pendingLinkHoverHideWorkItem = nil

            let forceClose = { [weak self] in
                guard let self else { return }
                self.activeLinkHoverSignature = nil
                self.isHoveringLinkPreviewSource = false
                self.isHoveringLinkPreviewPopover = false
                if let popover = self.linkHoverPopover, popover.isShown {
                    popover.performClose(nil)
                }
            }

            let closeAction = { [weak self] in
                guard let self else { return }
                guard !self.isHoveringLinkPreviewSource, !self.isHoveringLinkPreviewPopover else { return }
                self.activeLinkHoverSignature = nil
                self.isHoveringLinkPreviewSource = false
                self.isHoveringLinkPreviewPopover = false
                if let popover = self.linkHoverPopover, popover.isShown {
                    popover.performClose(nil)
                }
            }

            if immediate {
                forceClose()
                return
            }

            let workItem = DispatchWorkItem(block: closeAction)
            pendingLinkHoverHideWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
        }

        func popoverDidClose(_ notification: Notification) {
            guard let popover = notification.object as? NSPopover else { return }
            guard popover === linkHoverPopover else { return }
            activeLinkHoverSignature = nil
            isHoveringLinkPreviewSource = false
            isHoveringLinkPreviewPopover = false
        }
        
        private func handleLinkContextRequest(_ data: [String: Any]) {
            dismissLinkHoverPreview(immediate: true)
            guard let urlString = data["url"] as? String else { return }
            guard let url = URL(string: urlString) else { return }
            let request = WebViewLinkContextRequest(
                url: url,
                articleTitle: articleTitle(from: url),
                point: contextPoint(from: data)
            )
            presentNativeLinkContextMenu(for: request)
        }

        private func handleHighlightContextRequest(_ data: [String: Any]) {
            guard let idString = data["id"] as? String else { return }
            guard let uuid = UUID(uuidString: idString) else { return }
            let request = WebViewHighlightContextRequest(
                id: uuid,
                point: contextPoint(from: data)
            )
            presentNativeHighlightContextMenu(for: request)
        }

        private func articleTitle(from url: URL) -> String? {
            wikipediaLinkTarget(from: url)?.displayTitle
        }

        private func presentNativeLinkContextMenu(for request: WebViewLinkContextRequest) {
            guard let webView else { return }
            let menu = NSMenu(title: "")
            menu.autoenablesItems = false

            if request.articleTitle != nil {
                menu.addItem(linkMenuItem(
                    title: "Open",
                    systemImage: "arrow.up.forward",
                    action: .open,
                    request: request
                ))
                menu.addItem(linkMenuItem(
                    title: "Open in New Tab",
                    systemImage: "plus.square.on.square",
                    action: .openInNewTab,
                    request: request
                ))
                menu.addItem(linkMenuItem(
                    title: "Open in Background Tab",
                    systemImage: "square.on.square",
                    action: .openInNewBackgroundTab,
                    request: request
                ))

                let readingLists = fetchReadingLists()
                if !readingLists.isEmpty {
                    menu.addItem(.separator())
                    let saveToListItem = NSMenuItem(title: "Save to List", action: nil, keyEquivalent: "")
                    let saveToListMenu = NSMenu(title: "Save to List")
                    saveToListMenu.autoenablesItems = false

                    for list in readingLists {
                        let item = linkMenuItem(
                            title: list.name,
                            systemImage: list.icon,
                            action: .saveToList,
                            request: request,
                            readingListID: list.id
                        )
                        saveToListMenu.addItem(item)
                    }
                    saveToListItem.submenu = saveToListMenu
                    menu.addItem(saveToListItem)
                }

                menu.addItem(.separator())
                menu.addItem(linkMenuItem(
                    title: "Copy Title",
                    systemImage: "doc.on.doc",
                    action: .copyTitle,
                    request: request
                ))
            } else {
                menu.addItem(linkMenuItem(
                    title: "Open Link",
                    systemImage: "safari",
                    action: .open,
                    request: request
                ))
                menu.addItem(.separator())
            }

            menu.addItem(linkMenuItem(
                title: "Copy Link",
                systemImage: "link",
                action: .copyLink,
                request: request
            ))

            menu.popUp(positioning: nil, at: contextMenuPoint(request.point, in: webView), in: webView)
        }

        private func linkMenuItem(
            title: String,
            systemImage: String,
            action: LinkMenuAction,
            request: WebViewLinkContextRequest,
            readingListID: UUID? = nil
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(performLinkContextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = LinkMenuPayload(
                action: action,
                url: request.url,
                articleTitle: request.articleTitle,
                readingListID: readingListID
            )
            if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
                item.image = image
            }
            return item
        }

        @objc
        private func performLinkContextAction(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? LinkMenuPayload else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch payload.action {
                case .open:
                    self.openLinkFromContextMenu(payload.url, inNewTab: false)
                case .openInNewTab:
                    self.openLinkFromContextMenu(payload.url, inNewTab: true)
                case .openInNewBackgroundTab:
                    self.openLinkFromContextMenu(payload.url, inNewTab: true, activateNewTab: false)
                case .copyTitle:
                    if let title = payload.articleTitle {
                        _ = SystemBridge.copyText(title)
                    }
                case .copyLink:
                    _ = SystemBridge.copyText(payload.url.absoluteString)
                case .saveToList:
                    guard let title = payload.articleTitle,
                          let readingListID = payload.readingListID else { return }
                    self.saveLinkedArticle(title: title, to: readingListID)
                }
            }
        }

        private func openLinkFromContextMenu(_ url: URL, inNewTab: Bool, activateNewTab: Bool = true) {
            dismissLinkHoverPreview(immediate: true)
            if let target = wikipediaLinkTarget(from: url) {
                let normalizedCurrentTitle = normalizedArticleKey(articleTitle)
                let normalizedTargetTitle = normalizedArticleKey(target.displayTitle)
                let fragment = url.fragment?.trimmingCharacters(in: .whitespacesAndNewlines)
                if !inNewTab,
                   normalizedCurrentTitle == normalizedTargetTitle,
                   let fragment,
                   !fragment.isEmpty {
                    scrollToAnchor(fragment)
                    return
                }

                if inNewTab {
                    let article = Article(id: target.id, title: target.displayTitle)
                    appState?.openArticleInNewTab(article, activate: activateNewTab)
                } else {
                    onLinkTapped?(target.displayTitle)
                }
                return
            }

            if url.scheme != nil {
                _ = SystemBridge.openURLExternally(url)
            }
        }

        private func saveLinkFromHoverPreview(_ url: URL) {
            dismissLinkHoverPreview(immediate: true)
            guard let target = wikipediaLinkTarget(from: url) else { return }
            let article = Article(id: target.id, title: target.displayTitle)
            appState?.presentOptionClickSavePrompt(for: article)
        }

        private func presentNativeSelectionContextMenu(for request: WebViewSelectionContextRequest) {
            guard let webView else { return }

            let menu = NSMenu(title: "")
            menu.autoenablesItems = false

            let highlightMenuRoot = NSMenuItem(title: "Highlight", action: nil, keyEquivalent: "")
            let highlightMenu = NSMenu(title: "Highlight")
            highlightMenu.autoenablesItems = false
            for color in HighlightColor.allCases {
                highlightMenu.addItem(selectionColorMenuItem(
                    color: color,
                    action: .highlight(color),
                    request: request
                ))
            }
            highlightMenuRoot.submenu = highlightMenu
            menu.addItem(highlightMenuRoot)

            let noteMenuRoot = NSMenuItem(title: "Highlight with Note", action: nil, keyEquivalent: "")
            let noteMenu = NSMenu(title: "Highlight with Note")
            noteMenu.autoenablesItems = false
            for color in HighlightColor.allCases {
                noteMenu.addItem(selectionColorMenuItem(
                    color: color,
                    action: .highlightWithNote(color),
                    request: request
                ))
            }
            noteMenuRoot.submenu = noteMenu
            menu.addItem(noteMenuRoot)

            menu.addItem(.separator())
            menu.addItem(selectionMenuItem(
                title: "Copy Selection",
                systemImage: "doc.on.doc",
                action: .copySelection,
                request: request
            ))

            menu.popUp(positioning: nil, at: contextMenuPoint(request.point, in: webView), in: webView)
        }

        private func selectionColorMenuItem(
            color: HighlightColor,
            action: SelectionMenuAction,
            request: WebViewSelectionContextRequest
        ) -> NSMenuItem {
            let item = NSMenuItem(
                title: color.rawValue,
                action: #selector(performSelectionContextAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = SelectionMenuPayload(action: action, request: request)
            item.image = highlightColorSwatchImage(for: color)
            return item
        }

        private func selectionMenuItem(
            title: String,
            systemImage: String,
            action: SelectionMenuAction,
            request: WebViewSelectionContextRequest
        ) -> NSMenuItem {
            let item = NSMenuItem(
                title: title,
                action: #selector(performSelectionContextAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = SelectionMenuPayload(action: action, request: request)
            if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
                item.image = image
            }
            return item
        }

        @objc
        private func performSelectionContextAction(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? SelectionMenuPayload else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch payload.action {
                case .highlight(let color):
                    self.createHighlight(
                        from: payload.request.selection,
                        color: color,
                        note: nil
                    )
                case .highlightWithNote(let color):
                    if let highlightID = self.createHighlight(
                        from: payload.request.selection,
                        color: color,
                        note: nil
                    ) {
                        self.openHighlightNoteEditor(highlightID: highlightID)
                    }
                case .copySelection:
                    _ = SystemBridge.copyText(payload.request.selection.text)
                    self.appState?.currentTextSelection = nil
                }
            }
        }

        @discardableResult
        private func createHighlight(from selection: TextSelectionData, color: HighlightColor, note: String?) -> UUID? {
            guard let modelContext else { return nil }

            let highlight = Highlight(
                text: selection.text,
                articleTitle: articleTitle,
                elementPath: selection.elementPath,
                startOffset: selection.startOffset,
                length: selection.length,
                contextBefore: selection.contextBefore,
                contextAfter: selection.contextAfter,
                sectionTitle: selection.sectionTitle,
                color: color
            )
            highlight.note = note
            modelContext.insert(highlight)

            do {
                try modelContext.save()
                appState?.pendingImmediateHighlight = AppState.ImmediateHighlightRequest(
                    id: highlight.id,
                    cssColor: color.cssColor
                )
            } catch {
                return nil
            }

            appState?.currentTextSelection = nil
            return highlight.id
        }

        private func openHighlightNoteEditor(highlightID: UUID) {
            appState?.selectedHighlightId = highlightID.uuidString
            appState?.highlightTagFilterId = nil
            appState?.inspectorMode = .notes
            appState?.inspectorVisible = true
            appState?.pendingHighlightNoteEditorRequest = AppState.HighlightNoteEditorRequest(
                requestID: UUID(),
                highlightID: highlightID
            )
        }

        private func fetchReadingLists() -> [ReadingList] {
            guard let modelContext else { return [] }
            let descriptor = FetchDescriptor<ReadingList>(
                sortBy: [SortDescriptor(\ReadingList.updatedAt, order: .reverse)]
            )
            return (try? modelContext.fetch(descriptor)) ?? []
        }

        private func saveLinkedArticle(title: String, to readingListID: UUID) {
            guard let modelContext else { return }
            let targetListID = readingListID
            let descriptor = FetchDescriptor<ReadingList>(
                predicate: #Predicate { list in
                    list.id == targetListID
                }
            )
            guard let list = try? modelContext.fetch(descriptor).first else { return }

            let normalized = ReadStateSync.normalizedTitle(title)
            if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalized }) {
                return
            }

            let saved = SavedArticle(title: title, list: list)
            saved.isRead = ReadStateSync.resolveReadState(for: title, in: modelContext)
            list.articles.append(saved)
            list.updatedAt = Date()
            try? modelContext.save()
            SavedArticleSummaryBackfill.enqueueIfNeeded(saved, modelContext: modelContext)
            appState?.requestSave()
        }

        private func presentNativeHighlightContextMenu(for request: WebViewHighlightContextRequest) {
            guard let webView else { return }
            guard let highlight = highlights.first(where: { $0.id == request.id }) else { return }

            let menu = NSMenu(title: "")
            menu.autoenablesItems = false

            let colorMenuRoot = NSMenuItem(title: "Highlight Color", action: nil, keyEquivalent: "")
            let colorMenu = NSMenu(title: "Highlight Color")
            colorMenu.autoenablesItems = false

            for color in HighlightColor.allCases {
                colorMenu.addItem(
                    highlightColorMenuItem(
                        color: color,
                        isSelected: highlight.color == color,
                        highlightID: request.id
                    )
                )
            }

            colorMenuRoot.submenu = colorMenu
            menu.addItem(colorMenuRoot)
            menu.addItem(.separator())
            menu.addItem(highlightMenuItem(
                title: highlight.note == nil ? "Add Note" : "Edit Note",
                systemImage: "note.text",
                action: .editNote,
                highlightID: request.id
            ))
            menu.addItem(highlightMenuItem(
                title: "Delete Highlight",
                systemImage: "trash",
                action: .delete,
                highlightID: request.id
            ))

            menu.popUp(positioning: nil, at: contextMenuPoint(request.point, in: webView), in: webView)
        }

        private func highlightColorMenuItem(
            color: HighlightColor,
            isSelected: Bool,
            highlightID: UUID
        ) -> NSMenuItem {
            let item = NSMenuItem(
                title: color.rawValue,
                action: #selector(performHighlightContextAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = HighlightMenuPayload(action: .setColor(color), highlightID: highlightID)
            item.image = highlightColorSwatchImage(for: color)
            item.state = isSelected ? .on : .off
            return item
        }

        private func highlightMenuItem(
            title: String,
            systemImage: String,
            action: HighlightMenuAction,
            highlightID: UUID
        ) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(performHighlightContextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = HighlightMenuPayload(action: action, highlightID: highlightID)
            if let image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title) {
                item.image = image
            }
            return item
        }

        private func highlightColorSwatchImage(for color: HighlightColor) -> NSImage {
            let size = NSSize(width: 12, height: 12)
            let image = NSImage(size: size)
            image.lockFocus()

            let rect = NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let circle = NSBezierPath(ovalIn: rect)
            highlightSwatchColor(for: color).setFill()
            circle.fill()

            NSColor.labelColor.withAlphaComponent(0.18).setStroke()
            circle.lineWidth = 0.8
            circle.stroke()

            image.unlockFocus()
            image.isTemplate = false
            return image
        }

        private func highlightSwatchColor(for color: HighlightColor) -> NSColor {
            switch color {
            case .yellow:
                return NSColor(srgbRed: 1.0, green: 0.84, blue: 0.0, alpha: 1.0)
            case .blue:
                return NSColor(srgbRed: 0.23, green: 0.51, blue: 0.96, alpha: 1.0)
            case .pink:
                return NSColor(srgbRed: 0.93, green: 0.28, blue: 0.60, alpha: 1.0)
            case .orange:
                return NSColor(srgbRed: 0.98, green: 0.45, blue: 0.09, alpha: 1.0)
            }
        }

        @objc
        private func performHighlightContextAction(_ sender: NSMenuItem) {
            guard let payload = sender.representedObject as? HighlightMenuPayload else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch payload.action {
                case .setColor(let color):
                    self.updateHighlightColor(highlightID: payload.highlightID, color: color)
                case .editNote:
                    self.openHighlightInInspector(highlightID: payload.highlightID)
                case .delete:
                    self.deleteHighlight(highlightID: payload.highlightID)
                }
            }
        }

        private func openHighlightInInspector(highlightID: UUID) {
            appState?.selectedHighlightId = highlightID.uuidString
            appState?.inspectorMode = .notes
            appState?.inspectorVisible = true
        }

        private func updateHighlightColor(highlightID: UUID, color: HighlightColor) {
            guard let modelContext else { return }
            guard let highlight = highlights.first(where: { $0.id == highlightID }) else { return }
            guard highlight.color != color else { return }

            highlight.color = color
            highlight.updatedAt = Date()
            try? modelContext.save()
            appState?.pendingHighlightColorChange = AppState.HighlightColorChangeRequest(
                id: highlightID,
                cssColor: color.cssColor
            )
        }

        private func deleteHighlight(highlightID: UUID) {
            guard let modelContext else { return }
            guard let highlight = highlights.first(where: { $0.id == highlightID }) else { return }
            modelContext.delete(highlight)
            try? modelContext.save()
        }

        private func contextMenuPoint(_ point: CGPoint, in webView: WKWebView) -> CGPoint {
            let minInset: CGFloat = 6
            let maxX = max(minInset, webView.bounds.width - minInset)
            let x = min(max(point.x, minInset), maxX)

            let resolvedY = webView.isFlipped ? point.y : (webView.bounds.height - point.y)
            let maxY = max(minInset, webView.bounds.height - minInset)
            let y = min(max(resolvedY, minInset), maxY)
            return CGPoint(x: x, y: y)
        }

        private func contextPoint(from data: [String: Any]) -> CGPoint {
            CGPoint(
                x: numericValue(from: data["x"]) ?? 0,
                y: numericValue(from: data["y"]) ?? 0
            )
        }

        private func numericValue(from raw: Any?) -> CGFloat? {
            if let value = raw as? CGFloat { return value }
            if let value = raw as? Double { return CGFloat(value) }
            if let value = raw as? Int { return CGFloat(value) }
            if let value = raw as? NSNumber { return CGFloat(truncating: value) }
            return nil
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
            // Handle target="_blank" links
            if navigationAction.request.url != nil {
                // Determine if it's external or internal based on our logic
                // For simplicity, just load it in the same webview, which will trigger decidePolicyFor
                webView.load(navigationAction.request)
            }
            return nil
        }
        
        private var scrollObserver: NSObjectProtocol?
        
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

        func prepareHTMLForInitialLoad(_ htmlContent: String) -> String {
            guard htmlContent.range(of: "<img", options: .caseInsensitive) != nil,
                  let regex = Self.imgTagRegex else {
                return htmlContent
            }

            let source = htmlContent as NSString
            let matches = regex.matches(in: htmlContent, range: NSRange(location: 0, length: source.length))
            guard !matches.isEmpty else { return htmlContent }

            var rewritten = htmlContent
            var locationOffset = 0

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
                let previousLength = adjustedRange.length
                rewritten.replaceSubrange(swiftRange, with: tag)
                locationOffset += (tag as NSString).length - previousLength
            }

            return rewritten
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
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let expectedNavigationToken,
               let navigation,
               ObjectIdentifier(navigation) != expectedNavigationToken {
                return
            }
            isContentLoadInFlight = false
            expectedNavigationToken = nil
            webContentTerminationCount = 0
            hasUserDrivenScrollSinceLoad = false
            syncRestoreTelemetryMode(on: webView, force: true)
            self.webView = webView
            openTimer?.wrappedValue.markWebViewDidFinish()
            syncNativeHighlightMenuMode(on: webView, force: true)
            let restoreSessionID = beginRestoreSession()
            let scrollY = scrollPosition.wrappedValue
            let fallbackProgress = self.fallbackScrollProgress ?? 0
            let hasRestoreTarget = scrollY > 6 || fallbackProgress > 0.01
            let shouldDeferRevealUntilRestored = hasRestoreTarget

            applyReaderAppearance(to: webView, force: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                guard self.isRestoreSessionActive(restoreSessionID) else { return }
                if !shouldDeferRevealUntilRestored {
                    self.revealWebView(webView, animated: true)
                }
            }

            // Restore scroll position after load (with delay to ensure content is ready)
            let restoreGuardNow = Date().timeIntervalSinceReferenceDate
            configureInitialRestoreTelemetryGuard(
                scrollY: scrollY,
                fallbackProgress: fallbackProgress,
                now: restoreGuardNow
            )
            syncScrollTelemetryMode(on: webView, force: true)

            if scrollY > 0 {
                // First attempt immediately so restored position can settle before reveal probes.
                markProgrammaticScroll(y: scrollY)
                webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")

                // Include later retries to catch delayed layout growth from images/content.
                let restoreDelays: [TimeInterval]
                if preferImmediateReveal {
                    restoreDelays = [0.03, 0.09, 0.2, 0.38, 0.66, 1.0]
                } else {
                    restoreDelays = [0.08, 0.24, 0.55, 1.1, 1.9, 2.8]
                }
                for delay in restoreDelays {
                    scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.markProgrammaticScroll(y: scrollY)
                        webView.evaluateJavaScript("window.scrollTo(0, \(scrollY))")
                    }
                }
            } else if fallbackProgress > 0.01 {
                let clampedProgress = min(max(fallbackProgress, 0), 1)
                let restoreScript = """
                (function() {
                    var maxScroll = Math.max(
                        document.documentElement.scrollHeight,
                        document.body ? document.body.scrollHeight : 0
                    ) - window.innerHeight;
                    if (maxScroll > 0) {
                        window.scrollTo(0, maxScroll * \(clampedProgress));
                    }
                })();
                """
                // First attempt immediately so restored position can settle before reveal probes.
                markProgrammaticScroll()
                webView.evaluateJavaScript(restoreScript)

                let restoreDelays: [TimeInterval]
                if preferImmediateReveal {
                    restoreDelays = [0.03, 0.09, 0.2, 0.38, 0.66, 1.0]
                } else {
                    restoreDelays = [0.08, 0.24, 0.55, 1.1, 1.9, 2.8]
                }
                for delay in restoreDelays {
                    scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                        guard let self, let webView else { return }
                        self.markProgrammaticScroll()
                        webView.evaluateJavaScript(restoreScript)
                    }
                }
            }

            // Apply highlights before reveal so they are present on first visible frame.
            if !highlights.isEmpty {
                let highlightDelay: TimeInterval = preferImmediateReveal ? 0.03 : 0.12
                scheduleForRestoreSession(restoreSessionID, after: highlightDelay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.applyHighlights(to: webView)
                    self.openTimer?.wrappedValue.markHighlightsApplied()
                }
            }

            if shouldDeferRevealUntilRestored {
                scheduleRevealAfterRestore(
                    for: webView,
                    desiredY: scrollY,
                    fallbackProgress: fallbackProgress,
                    restoreSessionID: restoreSessionID
                )
            } else {
                // Failsafe reveal if JS callback is delayed.
                let failsafeDelay: TimeInterval = preferImmediateReveal ? 0.16 : 0.35
                scheduleForRestoreSession(restoreSessionID, after: failsafeDelay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.revealWebView(webView, animated: true)
                }
            }

            // Defer secondary work until reader surface is visible so warm/saved opens
            // prioritize first paint + restore over TOC/highlight initialization.
            hasTableOfContents = false
            runAfterReveal { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.setupScrollObserver(for: webView)

                self.scheduleForCurrentWebView(after: 0.04, webView: webView) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    if let scrollView = self.findScrollView(in: webView) {
                        self.reportScrollProgress(from: scrollView, force: true)
                    }
                    self.publishVisibleSection(from: webView, force: true)
                }

                self.scheduleForCurrentWebView(after: 0.06, webView: webView) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    self.publishTableOfContents(from: webView)
                    self.publishReferences(from: webView)
                }

                self.scheduleForCurrentWebView(after: 0.24, webView: webView) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    if !self.hasPublishedNonEmptyTOCSinceLoad {
                        self.publishTableOfContents(from: webView)
                    }
                    if !self.hasPublishedNonEmptyReferencesSinceLoad {
                        self.publishReferences(from: webView)
                    }
                    self.publishVisibleSection(from: webView, force: true)
                }
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webContentTerminationCount += 1
            guard webContentTerminationCount <= 2 else { return }

            // Keep the current surface visible during recovery to avoid a hard flash.
            isContentLoadInFlight = true
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            syncRestoreTelemetryMode(on: webView, force: true)
            if let recoveryHTMLPayload {
                let navigation = webView.loadHTMLString(
                    recoveryHTMLPayload,
                    baseURL: recoveryBaseURL ?? URL(string: "https://en.wikipedia.org/wiki/")
                )
                expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
            } else {
                let navigation = webView.reload()
                expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isContentLoadInFlight = false
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            syncRestoreTelemetryMode(on: webView, force: true)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isContentLoadInFlight = false
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            syncRestoreTelemetryMode(on: webView, force: true)
        }

        func applyReaderAppearance(to webView: WKWebView, force: Bool = false, completion: ((Bool) -> Void)? = nil) {
            let topInsetChanged = abs(lastAppliedReaderTopInset - readerTopInset) > 0.5
            guard force || lastAppliedReaderAppearance != readerAppearance || topInsetChanged else {
                completion?(true)
                return
            }
            guard let data = try? JSONSerialization.data(withJSONObject: readerAppearance.webPayload),
                  let jsonString = String(data: data, encoding: .utf8) else {
                completion?(false)
                return
            }

            let script = """
            window.setReaderAppearance(\(jsonString));
            document.documentElement.style.setProperty('--reader-top-inset', '\(Int(readerTopInset.rounded()))px');
            """
            webView.evaluateJavaScript(script) { [weak self] _, error in
                if error != nil {
                    completion?(false)
                    return
                }
                self?.lastAppliedReaderAppearance = self?.readerAppearance
                self?.lastAppliedReaderTopInset = self?.readerTopInset ?? -1
                completion?(true)
            }
        }

        func syncNativeHighlightMenuMode(on webView: WKWebView, force: Bool = false) {
            guard force || lastAppliedNativeHighlightingMenuEnabled != nativeHighlightingMenuEnabled else { return }
            lastAppliedNativeHighlightingMenuEnabled = nativeHighlightingMenuEnabled
            let enabledLiteral = nativeHighlightingMenuEnabled ? "true" : "false"
            let script = """
            window._macwikiNativeHighlightingMenuEnabled = \(enabledLiteral);
            if (window.setNativeHighlightingMenuEnabled) {
                window.setNativeHighlightingMenuEnabled(\(enabledLiteral));
            }
            """
            webView.evaluateJavaScript(script)
        }

        private func revealWebView(_ webView: WKWebView, animated: Bool? = nil) {
            guard webView.alphaValue < 1 else {
                notifyContentRevealIfNeeded()
                return
            }
            let shouldAnimate = animated ?? true
            guard shouldAnimate else {
                webView.alphaValue = 1
                notifyContentRevealIfNeeded()
                return
            }
            // Trigger overlay handoff at reveal start so skeleton fade and web reveal
            // run as a single crossfade instead of sequentially.
            notifyContentRevealIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = preferImmediateReveal ? 0.12 : 0.18
                webView.animator().alphaValue = 1
            }
        }

        private func notifyContentRevealIfNeeded() {
            guard !hasReportedContentReveal else { return }
            hasReportedContentReveal = true
            onContentReveal?()
            if !pendingPostRevealTasks.isEmpty {
                let tasks = pendingPostRevealTasks
                pendingPostRevealTasks.removeAll(keepingCapacity: false)
                for task in tasks {
                    task()
                }
            }
        }

        private func runAfterReveal(_ work: @escaping () -> Void) {
            if hasReportedContentReveal {
                work()
            } else {
                pendingPostRevealTasks.append(work)
            }
        }

        private func scheduleRevealAfterRestore(
            for webView: WKWebView,
            desiredY: CGFloat,
            fallbackProgress: Double,
            restoreSessionID: UUID
        ) {
            let checkpoints: [TimeInterval]
            if preferImmediateReveal {
                checkpoints = [0.02, 0.06, 0.13, 0.24, 0.42, 0.74]
            } else {
                checkpoints = [0.16, 0.38, 0.82, 1.45, 2.35, 3.35]
            }
            for (index, delay) in checkpoints.enumerated() {
                scheduleForRestoreSession(restoreSessionID, after: delay) { [weak self, weak webView] in
                    guard let self, let webView else { return }
                    guard webView.alphaValue < 1 else { return }

                    let probeScript = """
                    (function() {
                        var y = window.scrollY || window.pageYOffset || document.documentElement.scrollTop || 0;
                        var docHeight = Math.max(
                            document.documentElement ? document.documentElement.scrollHeight : 0,
                            document.body ? document.body.scrollHeight : 0
                        );
                        var maxScroll = Math.max(docHeight - window.innerHeight, 0);
                        var progress = maxScroll > 0 ? Math.min(Math.max(y / maxScroll, 0), 1) : 1;
                        return { y: y, progress: progress, maxScroll: maxScroll };
                    })();
                    """
                    webView.evaluateJavaScript(probeScript) { [weak self, weak webView] result, _ in
                        guard let self, let webView else { return }
                        guard self.isRestoreSessionActive(restoreSessionID) else { return }
                        let isFinalProbe = index == checkpoints.count - 1
                        if self.shouldRevealAfterRestoreProbe(
                            probeResult: result,
                            desiredY: desiredY,
                            fallbackProgress: fallbackProgress,
                            isFinalProbe: isFinalProbe
                        ) {
                            self.revealWebView(webView)
                        }
                    }
                }
            }
        }

        private func shouldRevealAfterRestoreProbe(
            probeResult: Any?,
            desiredY: CGFloat,
            fallbackProgress: Double,
            isFinalProbe: Bool
        ) -> Bool {
            if isFinalProbe {
                return true
            }

            guard let data = probeResult as? [String: Any] else {
                return false
            }

            let measuredY = (data["y"] as? Double).map { CGFloat($0) } ?? 0
            let measuredProgress = min(max(data["progress"] as? Double ?? 0, 0), 1)
            let maxScroll = data["maxScroll"] as? Double ?? 0

            if maxScroll <= 1 {
                return true
            }

            if desiredY > 6 {
                let positionTolerance = max(44, desiredY * 0.09)
                if abs(measuredY - desiredY) <= positionTolerance {
                    return true
                }
                if measuredY >= desiredY * (preferImmediateReveal ? 0.64 : 0.78) {
                    return true
                }
            } else if fallbackProgress > 0.01 {
                let clampedTargetProgress = min(max(fallbackProgress, 0), 1)
                if abs(measuredProgress - clampedTargetProgress) <= 0.07 {
                    return true
                }
                if measuredProgress >= clampedTargetProgress * (preferImmediateReveal ? 0.68 : 0.82) {
                    return true
                }
            } else {
                return true
            }

            return false
        }

        func resetPublishedTOCFingerprint() {
            lastPublishedTOCFingerprint = nil
        }

        func resetPublishedReferencesFingerprint() {
            lastPublishedReferencesFingerprint = nil
        }

        private static func tableOfContentsFingerprint(_ items: [ArticleTableOfContentsItem]) -> Int {
            var hasher = Hasher()
            hasher.combine(items.count)
            for item in items {
                hasher.combine(item.id)
                hasher.combine(item.title)
                hasher.combine(item.level)
            }
            return hasher.finalize()
        }

        private static func referencesFingerprint(_ sections: [ArticleReferenceSection]) -> Int {
            var hasher = Hasher()
            hasher.combine(sections.count)
            for section in sections {
                hasher.combine(section.id)
                hasher.combine(section.title)
                hasher.combine(section.items.count)
                for item in section.items {
                    hasher.combine(item.id)
                    hasher.combine(item.label)
                    hasher.combine(item.text)
                    hasher.combine(item.html)
                    hasher.combine(item.group)
                    hasher.combine(item.links.count)
                    for link in item.links {
                        hasher.combine(link)
                    }
                }
            }
            return hasher.finalize()
        }

        func publishTableOfContents(from webView: WKWebView) {
            guard !isTOCPublishInFlight else { return }
            isTOCPublishInFlight = true
            webView.evaluateJavaScript("window.extractTableOfContents();") { [weak self] result, error in
                guard let self else { return }
                defer { self.isTOCPublishInFlight = false }
                if error != nil {
                    return
                }

                guard let rows = result as? [[String: Any]] else {
                    self.hasTableOfContents = false
                    let fingerprint = Self.tableOfContentsFingerprint([])
                    guard self.lastPublishedTOCFingerprint != fingerprint else { return }
                    self.lastPublishedTOCFingerprint = fingerprint
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
                self.hasTableOfContents = !items.isEmpty
                if !items.isEmpty {
                    self.hasPublishedNonEmptyTOCSinceLoad = true
                }
                let fingerprint = Self.tableOfContentsFingerprint(items)
                guard self.lastPublishedTOCFingerprint != fingerprint else { return }
                self.lastPublishedTOCFingerprint = fingerprint

                DispatchQueue.main.async {
                    self.onTableOfContentsUpdate?(items)
                }
            }
        }

        func publishReferences(from webView: WKWebView) {
            guard !isReferencesPublishInFlight else { return }
            isReferencesPublishInFlight = true
            webView.evaluateJavaScript("window.extractReferences ? window.extractReferences() : [];") { [weak self] result, error in
                guard let self else { return }
                defer { self.isReferencesPublishInFlight = false }
                if error != nil {
                    return
                }

                guard let rows = result as? [[String: Any]] else {
                    let fingerprint = Self.referencesFingerprint([])
                    guard self.lastPublishedReferencesFingerprint != fingerprint else { return }
                    self.lastPublishedReferencesFingerprint = fingerprint
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
                if !sections.isEmpty {
                    self.hasPublishedNonEmptyReferencesSinceLoad = true
                }
                let fingerprint = Self.referencesFingerprint(sections)
                guard self.lastPublishedReferencesFingerprint != fingerprint else { return }
                self.lastPublishedReferencesFingerprint = fingerprint

                DispatchQueue.main.async {
                    self.onReferencesUpdate?(sections)
                }
            }
        }

        func publishVisibleSection(from webView: WKWebView, force: Bool = false) {
            webView.evaluateJavaScript("window.currentVisibleSectionId ? window.currentVisibleSectionId() : null;") { [weak self] result, _ in
                guard let self else { return }
                let sectionId = result as? String
                if force || sectionId != self.lastReportedVisibleSectionId {
                    self.lastReportedVisibleSectionId = sectionId
                    DispatchQueue.main.async {
                        self.onVisibleSectionChange?(sectionId)
                    }
                }
            }
        }
        
        func setupScrollObserver(for webView: WKWebView) {
            // Find the underlying NSScrollView
            guard let scrollView = findScrollView(in: webView) else { return }

            // Remove existing observer if any
            cleanup()

            // Required for NSView.boundsDidChangeNotification while user scrolls.
            scrollView.contentView.postsBoundsChangedNotifications = true

            // Observe bounds changes on the clip view (content view)
            scrollObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak webView] _ in
                guard let self = self else { return }
                // Safe because queue is main
                MainActor.assumeIsolated {
                    // JS telemetry is the primary source; only use this observer as fallback.
                    let now = Date().timeIntervalSinceReferenceDate
                    if now - self.lastJSTelemetryTimestamp < 0.95 {
                        return
                    }
                    if self.isContentLoadInFlight {
                        return
                    }
                    if self.isProgrammaticScrollActive(now: now) {
                        return
                    }
                    if now < self.highVelocityUserScrollUntil {
                        return
                    }

                    let currentY = scrollView.contentView.bounds.origin.y
                    if self.shouldIgnoreInitialTopTelemetry(y: currentY, progress: nil, now: now) {
                        return
                    }
                    self.lastKnownScrollY = currentY

                    let delta = abs(self.scrollPosition.wrappedValue - currentY)
                    let shouldPublishScrollPosition =
                        delta > self.adaptiveFallbackDeltaThreshold ||
                        ((now - self.lastScrollPositionPublishTimestamp) > self.adaptiveFallbackTimeGate && delta > 3)

                    if shouldPublishScrollPosition {
                        self.scrollPosition.wrappedValue = currentY
                        self.lastScrollPositionPublishTimestamp = now
                        self.requestSaveIfNeeded()
                    }

                    self.reportScrollProgress(from: scrollView, currentY: currentY)

                    // Fallback visible section update when JS telemetry is silent.
                    // Throttle to ~300ms to avoid flooding evaluateJavaScript calls.
                    if self.hasTableOfContents,
                       self.isSectionTrackingRequested,
                       now - self.lastVisibleSectionPollTimestamp > 0.3,
                       let webView {
                        self.lastVisibleSectionPollTimestamp = now
                        self.publishVisibleSection(from: webView)
                    }
                }
            }
        }

        private func requestSaveIfNeeded(force: Bool = false) {
            let now = Date().timeIntervalSinceReferenceDate
            if !force, isProgrammaticScrollActive(now: now) {
                return
            }
            if !force, now < highVelocityUserScrollUntil {
                return
            }
            if force || (now - lastSaveRequestTimestamp) >= adaptiveSaveRequestInterval {
                lastSaveRequestTimestamp = now
                appState?.requestSave()
            }
        }

        func prepareForContentReload() {
            dismissLinkHoverPreview(immediate: true)
            lastReportedProgress = -1
            lastProgressTimestamp = 0
            hasUserDrivenScrollSinceLoad = false
            clearInitialRestoreTelemetryGuard()
            isContentLoadInFlight = true
            expectedNavigationToken = nil
            activeRestoreSessionID = nil
            hasProgrammaticScrollInFlight = false
            programmaticScrollActiveUntil = 0
            highVelocityUserScrollUntil = 0
            hasReportedContentReveal = false
            pendingPostRevealTasks.removeAll(keepingCapacity: false)
            lastPublishedTOCFingerprint = nil
            lastPublishedReferencesFingerprint = nil
            hasPublishedNonEmptyTOCSinceLoad = false
            hasPublishedNonEmptyReferencesSinceLoad = false
            isTOCPublishInFlight = false
            isReferencesPublishInFlight = false
        }

        func beginContentReload(on webView: WKWebView, htmlContent: String, baseURL: URL?) {
            isContentLoadInFlight = true
            syncRestoreTelemetryMode(on: webView, force: true)
            let navigation = webView.loadHTMLString(htmlContent, baseURL: baseURL)
            expectedNavigationToken = navigation.map { ObjectIdentifier($0) }
        }

        private func beginRestoreSession() -> UUID {
            let sessionID = UUID()
            activeRestoreSessionID = sessionID
            return sessionID
        }

        private func isRestoreSessionActive(_ sessionID: UUID) -> Bool {
            activeRestoreSessionID == sessionID
        }

        private func scheduleForRestoreSession(
            _ sessionID: UUID,
            after delay: TimeInterval,
            _ work: @escaping () -> Void
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.isRestoreSessionActive(sessionID) else { return }
                work()
            }
        }

        private func scheduleForCurrentWebView(
            after delay: TimeInterval,
            webView expectedWebView: WKWebView,
            _ work: @escaping () -> Void
        ) {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak expectedWebView] in
                guard let self, let expectedWebView else { return }
                guard self.webView === expectedWebView else { return }
                work()
            }
        }

        private func clearInitialRestoreTelemetryGuard() {
            suppressInitialScrollPersistenceUntil = 0
            hasPendingNonZeroRestore = false
            pendingNonZeroRestoreDeadline = 0
            pendingRestoreUnlockProgress = 0.08
            pendingRestoreUnlockY = 80
        }

        private func configureInitialRestoreTelemetryGuard(
            scrollY: CGFloat,
            fallbackProgress: Double,
            now: TimeInterval
        ) {
            let clampedFallback = min(max(fallbackProgress, 0), 1)
            let shouldGuardInitialTopTelemetry = scrollY > 6 || clampedFallback > 0.01
            guard shouldGuardInitialTopTelemetry else {
                clearInitialRestoreTelemetryGuard()
                return
            }

            suppressInitialScrollPersistenceUntil = now + 1.15
            hasPendingNonZeroRestore = true
            pendingNonZeroRestoreDeadline = now + 3.8

            if scrollY > 6 {
                pendingRestoreUnlockY = min(max(scrollY * 0.24, 80), 520)
            } else if clampedFallback > 0.35 {
                pendingRestoreUnlockY = 120
            } else {
                pendingRestoreUnlockY = 80
            }

            if clampedFallback > 0.01 {
                pendingRestoreUnlockProgress = min(max(clampedFallback * 0.55, 0.08), 0.30)
            } else {
                pendingRestoreUnlockProgress = 0.12
            }
        }

        private func markProgrammaticScroll(
            y: CGFloat? = nil,
            activeFor duration: TimeInterval = 0.22
        ) {
            let now = Date().timeIntervalSinceReferenceDate
            lastProgrammaticScrollTimestamp = now
            programmaticScrollActiveUntil = max(programmaticScrollActiveUntil, now + max(duration, 0.08))
            if let y {
                lastKnownScrollY = y
            }
        }

        private func isProgrammaticScrollActive(now: TimeInterval) -> Bool {
            if hasProgrammaticScrollInFlight {
                return true
            }
            if now < programmaticScrollActiveUntil {
                return true
            }
            return (now - lastProgrammaticScrollTimestamp) < 0.16
        }

        private func noteUserDrivenScroll(now: TimeInterval) {
            let wasProgrammatic = (now - lastProgrammaticScrollTimestamp) < 0.26
            guard !wasProgrammatic else { return }
            hasUserDrivenScrollSinceLoad = true
            hasProgrammaticScrollInFlight = false
            programmaticScrollActiveUntil = now

            if activeRestoreSessionID != nil {
                activeRestoreSessionID = nil
                clearInitialRestoreTelemetryGuard()
                if let webView, webView.alphaValue < 1 {
                    revealWebView(webView, animated: false)
                }
            }
        }

        private func shouldIgnoreInitialTopTelemetry(y: CGFloat, progress: Double?, now: TimeInterval) -> Bool {
            // During initial restore retries, ignore transient top-of-page callbacks.
            // Without this, rapid article switches can persist y/progress=0 before restore completes.
            if hasPendingNonZeroRestore {
                let clampedProgress = min(max(progress ?? 0, 0), 1)
                let unlockedByY = y >= pendingRestoreUnlockY
                let unlockedByProgress = clampedProgress >= pendingRestoreUnlockProgress && y > 12
                let suspiciousTopCompletion = y < 14 && clampedProgress > 0.97
                let remainsNearTop = y < 14 && clampedProgress < 0.08

                if unlockedByY || unlockedByProgress {
                    hasPendingNonZeroRestore = false
                    pendingNonZeroRestoreDeadline = 0
                    suppressInitialScrollPersistenceUntil = 0
                } else if now < pendingNonZeroRestoreDeadline, (remainsNearTop || suspiciousTopCompletion) {
                    return true
                } else if now < pendingNonZeroRestoreDeadline {
                    return true
                } else {
                    hasPendingNonZeroRestore = false
                    pendingNonZeroRestoreDeadline = 0
                }
            }

            if now < suppressInitialScrollPersistenceUntil {
                return true
            }
            return false
        }

        func syncScrollTelemetryMode(on webView: WKWebView, force: Bool = false) {
            let desired = isSectionTrackingRequested
            guard force || lastAppliedSectionTrackingRequest != desired else { return }
            let script = "window.setScrollTelemetrySectionTrackingEnabled && window.setScrollTelemetrySectionTrackingEnabled(\(desired ? "true" : "false"));"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error == nil else { return }
                self?.lastAppliedSectionTrackingRequest = desired
            }
        }

        func syncRestoreTelemetryMode(on webView: WKWebView, force: Bool = false) {
            let desired = isContentLoadInFlight
            guard force || lastAppliedRestoreTelemetryMode != desired else { return }
            let script = "window.setRestoreTelemetryMode && window.setRestoreTelemetryMode(\(desired ? "true" : "false"));"
            webView.evaluateJavaScript(script) { [weak self] _, error in
                guard error == nil else { return }
                self?.lastAppliedRestoreTelemetryMode = desired
            }
        }

        private func applyScrollProfile(_ profile: ScrollProfile) {
            guard profile != currentScrollProfile else { return }
            currentScrollProfile = profile
            switch profile {
            case .responsive:
                adaptiveScrollDeltaThreshold = 12
                adaptiveScrollTimeGate = 0.75
                adaptiveProgressDeltaThreshold = 0.035
                adaptiveProgressTimeGate = 1.25
                adaptiveSaveRequestInterval = 3.0
                adaptiveFallbackDeltaThreshold = 13
                adaptiveFallbackTimeGate = 1.2
            case .balanced:
                adaptiveScrollDeltaThreshold = 14
                adaptiveScrollTimeGate = 0.9
                adaptiveProgressDeltaThreshold = 0.045
                adaptiveProgressTimeGate = 1.6
                adaptiveSaveRequestInterval = 3.4
                adaptiveFallbackDeltaThreshold = 14
                adaptiveFallbackTimeGate = 1.4
            case .economy:
                adaptiveScrollDeltaThreshold = 18
                adaptiveScrollTimeGate = 1.15
                adaptiveProgressDeltaThreshold = 0.06
                adaptiveProgressTimeGate = 2.1
                adaptiveSaveRequestInterval = 4.0
                adaptiveFallbackDeltaThreshold = 18
                adaptiveFallbackTimeGate = 1.8
            }
        }

        func restoreScrollPositionIfNeeded(on webView: WKWebView, desiredY: CGFloat) {
            let now = Date().timeIntervalSinceReferenceDate
            if isContentLoadInFlight {
                return
            }
            if hasUserDrivenScrollSinceLoad || activeRestoreSessionID != nil {
                return
            }
            if (now - lastJSTelemetryTimestamp) < 0.35 {
                return
            }
            if isProgrammaticScrollActive(now: now) {
                return
            }

            let delta = abs(lastKnownScrollY - desiredY)
            guard delta > 6 else { return }

            let script = "window.scrollTo(0, \(desiredY));"
            markProgrammaticScroll(y: desiredY)
            webView.evaluateJavaScript(script)
        }

        private func reportScrollProgress(from scrollView: NSScrollView, currentY: CGFloat? = nil, force: Bool = false) {
            let contentHeight = scrollView.documentView?.bounds.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let maxScroll = max(contentHeight - viewportHeight, 0)
            let offsetY = currentY ?? scrollView.contentView.bounds.origin.y
            let rawProgress = maxScroll > 0 ? Double(offsetY / maxScroll) : 1
            let clamped = min(max(rawProgress, 0), 1)
            reportScrollProgressValue(clamped, force: force)
        }

        private func reportScrollProgressValue(_ progress: Double, force: Bool = false) {
            if isContentLoadInFlight {
                return
            }
            let clamped = min(max(progress, 0), 1)
            let now = Date().timeIntervalSinceReferenceDate
            if shouldIgnoreInitialTopTelemetry(y: lastKnownScrollY, progress: clamped, now: now) {
                return
            }
            let progressDelta = abs(clamped - lastReportedProgress)
            let timeDelta = now - lastProgressTimestamp
            // Keep reader progress indicators responsive without flooding model writes.
            if force || progressDelta >= adaptiveProgressDeltaThreshold || timeDelta >= adaptiveProgressTimeGate {
                lastReportedProgress = clamped
                lastProgressTimestamp = now
                onScrollProgress?(clamped)
            }
        }
        
        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let webView = view as? WKWebView {
                return webView.enclosingScrollView
            }
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            
            for subview in view.subviews {
                if let found = findScrollView(in: subview) {
                    return found
                }
            }
            
            return nil
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

private enum ScrollProfile {
    case responsive
    case balanced
    case economy
}
