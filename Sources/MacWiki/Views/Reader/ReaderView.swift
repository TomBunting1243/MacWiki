import SwiftUI
import SwiftData

private enum ReaderMotion {
    static let surfaceSwap = Animation.easeOut(duration: 0.22)
    static let surfaceInsertionScale: CGFloat = 0.995
    static let webRevealDuration: Double = 0.20
    static let hoverPreviewInsertionScale: CGFloat = 0.975
    static let hoverPreviewHapticDelay: Double = 0.08
    static let hoverPreviewHapticCooldown: TimeInterval = 0.30
    static let skeletonRevealDuration: Double = AppLoadingMotion.skeletonRevealDuration
    static let skeletonHideDuration: Double = AppLoadingMotion.skeletonHideDuration
    static let promptSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let promptShowResponse: Double = 0.30
    static let promptShowDamping: Double = 0.82
    static let promptPrimaryDismissResponse: Double = 0.26
    static let promptPrimaryDismissDamping: Double = 0.84
    static let promptSecondaryDismissResponse: Double = 0.22
    static let promptSecondaryDismissDamping: Double = 0.88
    static let promptCornerRadius: CGFloat = 21
}

private enum LinkHoverOverlayMetrics {
    static let edgeInset: CGFloat = 14
    static let attachmentGap: CGFloat = 8
    static let leadingBias: CGFloat = 28
    static let hoverHaloInset: CGFloat = 18
}

private struct ReaderLinkHoverPreviewOverlay: View {
    let request: WebViewLinkHoverRequest
    let onOpen: () -> Void
    let onOpenInNewTab: () -> Void
    let onOpenInNewWindow: () -> Void
    let onSave: () -> Void
    var onReveal: () -> Void = {}
    var onHoverStateChange: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var preferredPreviewHeight: CGFloat = LinkHoverPreviewMetrics.height

    private var previewSwapTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .opacity.combined(with: .scale(scale: 0.988, anchor: .top))
    }

    var body: some View {
        GeometryReader { proxy in
            let previewSize = resolvedPreviewSize(in: proxy.size)
            let interactiveSize = resolvedInteractiveSize(for: previewSize)
            let interactiveOrigin = resolvedInteractiveOrigin(
                for: previewSize,
                interactiveSize: interactiveSize,
                in: proxy.size
            )

            ZStack {
                LinkHoverPreviewPane(
                    title: request.articleTitle ?? "Article",
                    fallbackURL: request.url,
                    onOpen: onOpen,
                    onOpenInNewTab: onOpenInNewTab,
                    onOpenInNewWindow: onOpenInNewWindow,
                    onSave: onSave,
                    previewSize: previewSize,
                    onPreferredHeightChange: { newHeight in
                        let availableHeight = max(
                            0,
                            proxy.size.height -
                                (LinkHoverOverlayMetrics.edgeInset * 2) -
                                (LinkHoverOverlayMetrics.hoverHaloInset * 2)
                        )
                        let clampedHeight = min(
                            max(newHeight, LinkHoverPreviewMetrics.height),
                            availableHeight
                        )
                        guard abs(preferredPreviewHeight - clampedHeight) > 0.5 else { return }
                        preferredPreviewHeight = clampedHeight
                    }
                )
                .id(request.signature)
                .transition(previewSwapTransition)
            }
            .padding(LinkHoverOverlayMetrics.hoverHaloInset)
            .frame(width: interactiveSize.width, height: interactiveSize.height)
            .contentShape(Rectangle())
            .onHover(perform: onHoverStateChange)
            .position(
                x: interactiveOrigin.x + (interactiveSize.width * 0.5),
                y: interactiveOrigin.y + (interactiveSize.height * 0.5)
            )
            .onAppear(perform: onReveal)
            .onChange(of: request.signature) { oldSignature, newSignature in
                guard oldSignature != newSignature else { return }
                preferredPreviewHeight = LinkHoverPreviewMetrics.height
                onReveal()
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: request.signature)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func resolvedPreviewSize(in container: CGSize) -> CGSize {
        let availableWidth = max(
            0,
            container.width -
                (LinkHoverOverlayMetrics.edgeInset * 2) -
                (LinkHoverOverlayMetrics.hoverHaloInset * 2)
        )
        let availableHeight = max(
            0,
            container.height -
                (LinkHoverOverlayMetrics.edgeInset * 2) -
                (LinkHoverOverlayMetrics.hoverHaloInset * 2)
        )
        return CGSize(
            width: min(LinkHoverPreviewMetrics.width, availableWidth),
            height: min(max(preferredPreviewHeight, LinkHoverPreviewMetrics.height), availableHeight)
        )
    }

    private func resolvedInteractiveSize(for previewSize: CGSize) -> CGSize {
        CGSize(
            width: previewSize.width + (LinkHoverOverlayMetrics.hoverHaloInset * 2),
            height: previewSize.height + (LinkHoverOverlayMetrics.hoverHaloInset * 2)
        )
    }

    private func resolvedInteractiveOrigin(
        for previewSize: CGSize,
        interactiveSize: CGSize,
        in container: CGSize
    ) -> CGPoint {
        let minX = LinkHoverOverlayMetrics.edgeInset
        let maxX = max(minX, container.width - interactiveSize.width - LinkHoverOverlayMetrics.edgeInset)
        let preferredX =
            request.point.x -
            LinkHoverOverlayMetrics.leadingBias -
            LinkHoverOverlayMetrics.hoverHaloInset
        let originX = min(max(preferredX, minX), maxX)

        let minY = LinkHoverOverlayMetrics.edgeInset
        let maxY = max(minY, container.height - interactiveSize.height - LinkHoverOverlayMetrics.edgeInset)
        let preferredBelowY =
            request.point.y +
            LinkHoverOverlayMetrics.attachmentGap -
            LinkHoverOverlayMetrics.hoverHaloInset
        let preferredAboveY =
            request.point.y -
            previewSize.height -
            LinkHoverOverlayMetrics.attachmentGap -
            LinkHoverOverlayMetrics.hoverHaloInset
        let originY: CGFloat
        if preferredBelowY <= maxY {
            originY = min(max(preferredBelowY, minY), maxY)
        } else {
            originY = min(max(preferredAboveY, minY), maxY)
        }

        return CGPoint(x: originX, y: originY)
    }
}

/// Reader view - shows article content or new tab page
struct ReaderView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            if let activeId = appState.activeTabId,
               let index = appState.openTabs.firstIndex(where: { $0.id == activeId }) {
                let activeTab = appState.openTabs[index]
                let activeHistoryItemID = activeTab.currentHistoryItem?.id

                if activeTab.isPlaceholder {
                    // Show new tab page with search
                    NewTabPageView()
                } else if let article = activeTab.currentArticle {
                    // Show article content
                    ArticleView(
                        tabId: activeId,
                        article: article,
                        scrollPosition: Binding(
                            get: {
                                appState.scrollPosition(
                                    forTabID: activeId,
                                    historyItemID: activeHistoryItemID
                                )
                            },
                            set: {
                                appState.setScrollPosition(
                                    $0,
                                    forTabID: activeId,
                                    historyItemID: activeHistoryItemID
                                )
                            }
                        )
                    )
                } else {
                    NewTabPageView()
                }
            } else {
                ContentUnavailableView(
                    "Welcome to MacWiki",
                    systemImage: "book.pages",
                    description: Text("Press ⌘K to search for an article")
                )
            }
        }
        .id(activeReaderSurfaceID)
        .transition(
            reduceMotion
                ? .identity
                : .asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: ReaderMotion.surfaceInsertionScale)),
                    removal: .opacity
                )
        )
        .animation(
            reduceMotion ? nil : ReaderMotion.surfaceSwap,
            value: activeReaderSurfaceID
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            WebViewPool.shared.retain(only: Set(appState.openTabs.map(\.id)), for: appState.webViewPoolOwnerID)
        }
        .onChange(of: appState.openTabs.map(\.id)) { _, tabIDs in
            WebViewPool.shared.retain(only: Set(tabIDs), for: appState.webViewPoolOwnerID)
        }
        .onDisappear {
            WebViewPool.shared.releaseOwner(appState.webViewPoolOwnerID)
        }
    }

    private var activeReaderSurfaceID: String {
        guard let activeId = appState.activeTabId,
              let tab = appState.openTabs.first(where: { $0.id == activeId }) else {
            return "reader-surface-empty"
        }

        if tab.isPlaceholder {
            return "reader-surface-discover-\(activeId.uuidString)"
        }
        return "reader-surface-article-\(activeId.uuidString)-\(tab.article.id)"
    }
}
/// New tab page routes to the dedicated Discover experience.
struct NewTabPageView: View {
    var body: some View {
        DiscoverNewTabPageView()
    }
}

/// Article view with WebView content rendering
struct ArticleView: View {
    private struct PendingHydratedMetadata: Equatable {
        let articleID: String
        let articleTitle: String
        let items: [WikipediaService.MetadataItem]
        let wordCount: Int
    }

    let tabId: UUID
    let article: Article
    @Binding var scrollPosition: CGFloat
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.readerChromeMetrics) private var readerChromeMetrics
    @Query(sort: \ReadingList.updatedAt, order: .reverse) private var allLists: [ReadingList]
    @Query private var highlightsForArticle: [Highlight]

    @State private var htmlContent: String?
    @State private var loadedArticleKey: String?
    @State private var isLoading = true
    @State private var isWebContentReady = false
    @State private var hasPublishedLiveReadingProgressForCurrentOpen = false
    @State private var isLoadingSkeletonVisible = false
    @State private var loadingSkeletonShownAt: TimeInterval = 0
    @State private var skeletonVisibilityTicket = UUID()
    @State private var articleViewportWidth: CGFloat = 960
    @State private var topObscuredHeight: CGFloat = 38
    @State private var suppressLoadingSkeletonForCurrentOpen = false
    @State private var errorMessage: String?
    @State private var preferImmediateWebReveal = false
    @State private var showMarkAsReadPrompt = false
    @State private var isArticleUnreadState = true
    @State private var progressCoordinator = ReaderProgressCoordinator()
    @State private var articleLoader = ReaderArticleLoader()
    @State private var promptPolicy = ReaderPromptPolicy()
    @State private var openTimer = ArticleOpenTimer()
    @State private var pendingHydratedMetadata: PendingHydratedMetadata?
    @State private var linkHoverPreviewRequest: WebViewLinkHoverRequest?
    @State private var isHoveringLinkHoverPreview = false
    @State private var pendingLinkHoverRevealHapticTask: Task<Void, Never>?
    @State private var lastLinkHoverRevealHapticTimestamp: TimeInterval = 0
    @AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = .system
    @AppStorage(ReaderAppearanceStorageKey.fontSize) private var readerFontSize: Double = ReaderAppearance.default.fontSize
    @AppStorage(ReaderAppearanceStorageKey.lineHeight) private var readerLineHeight: Double = ReaderAppearance.default.lineHeight
    @AppStorage(ReaderAppearanceStorageKey.paragraphSpacing) private var readerParagraphSpacing: Double = ReaderAppearance.default.paragraphSpacing
    @AppStorage(ReaderAppearanceStorageKey.contentWidth) private var readerContentWidth: Double = ReaderAppearance.default.contentWidth
    @AppStorage(ReaderAppearanceStorageKey.horizontalPadding) private var readerHorizontalPadding: Double = ReaderAppearance.default.horizontalPadding
    @AppStorage(ReaderAppearanceStorageKey.headingScale) private var readerHeadingScale: Double = ReaderAppearance.default.headingScale
    @AppStorage(AppStorageKey.Reader.linkPreviewImmediateModifier) private var linkPreviewImmediateModifier: ReaderLinkPreviewImmediateModifier = .default
    @AppStorage(AppStorageKey.Chrome.liquidGlassChrome) private var liquidGlassChrome = true
    @AppStorage(MacWikiGlassRuntime.forceLegacyFallbackKey) private var forceLegacyGlassFallback = false

    init(tabId: UUID, article: Article, scrollPosition: Binding<CGFloat>) {
        self.tabId = tabId
        self.article = article
        self._scrollPosition = scrollPosition

        let articleTitle = article.title
        self._highlightsForArticle = Query(
            filter: #Predicate<Highlight> { $0.articleTitle == articleTitle && $0.isArchivedRaw != true }
        )
    }

    /// Highlights for current article
    private var articleHighlights: [Highlight] {
        highlightsForArticle
    }

    private var articleIsSavedInAnyList: Bool {
        let normalized = ReadStateSync.normalizedTitle(article.title)
        for list in allLists {
            if list.articles.contains(where: { ReadStateSync.normalizedTitle($0.title) == normalized }) {
                return true
            }
        }
        return false
    }

    private var shouldPinArticleBodyCache: Bool {
        articleIsSavedInAnyList || !articleHighlights.isEmpty
    }

    private var readerAppearance: ReaderAppearance {
        ReaderAppearance(
            fontPreset: readerFontPreset,
            fontSize: readerFontSize,
            lineHeight: readerLineHeight,
            paragraphSpacing: readerParagraphSpacing,
            contentWidth: readerContentWidth,
            horizontalPadding: readerHorizontalPadding,
            headingScale: readerHeadingScale
        )
    }

    private var resolvedReaderAppearance: ReaderAppearance {
        readerAppearance.resolvedForViewportWidth(Double(articleViewportWidth))
    }

    private var resolvedTopObscuredHeight: CGFloat {
        max(topObscuredHeight, readerChromeMetrics.topObscuredHeight)
    }

    private var readerTopInset: CGFloat {
        let hasToolbarControls = !appState.isWikiHopNavigationLocked
        let compactWidthBoost: CGFloat
        switch articleViewportWidth {
        case ..<520:
            compactWidthBoost = 14
        case ..<680:
            compactWidthBoost = 10
        case ..<820:
            compactWidthBoost = 6
        default:
            compactWidthBoost = 0
        }
        let resolved: CGFloat
        if hasToolbarControls {
            let chromeOverlapInset = max(
                readerChromeMetrics.titlebarTabStripHeight + 8,
                resolvedTopObscuredHeight - 44
            )
            resolved = chromeOverlapInset + compactWidthBoost
        } else {
            resolved = resolvedTopObscuredHeight + 8
        }
        return max(resolved, 0)
    }

    private var findOnPageTopPadding: CGFloat {
        let hasToolbarControls = !appState.isWikiHopNavigationLocked
        let compactWidthBoost: CGFloat
        switch articleViewportWidth {
        case ..<680:
            compactWidthBoost = 4
        default:
            compactWidthBoost = 0
        }
        if hasToolbarControls {
            return resolvedTopObscuredHeight + 8 + compactWidthBoost
        }
        return max(10, resolvedTopObscuredHeight + 10) + compactWidthBoost
    }

    private var usesNativeFindNavigator: Bool {
        return false
    }

    private var findNavigatorPresentedBinding: Binding<Bool> {
        Binding(
            get: { appState.showFindOnPage },
            set: { appState.showFindOnPage = $0 }
        )
    }

    private var shouldShowLoadingSkeleton: Bool {
        errorMessage == nil &&
        !suppressLoadingSkeletonForCurrentOpen &&
        isLoadingSkeletonVisible &&
        (isLoading || !isWebContentReady)
    }

    private var loadingTransition: AnyTransition {
        AppLoadingMotion.overlayTransition(reduceMotion: reduceMotion, anchor: .top)
    }

    private var findTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private var markPromptTransition: AnyTransition {
        reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var linkHoverPreviewTransition: AnyTransition {
        reduceMotion
            ? .identity
            : .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: ReaderMotion.hoverPreviewInsertionScale, anchor: .top)),
                removal: .opacity
            )
    }
    
    var body: some View {
        content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ReaderSurfacePalette.surface(for: colorScheme)
                .ignoresSafeArea()
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateArticleViewportWidth(proxy.size.width)
                        updateTopObscuredHeight(proxy.safeAreaInsets.top)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateArticleViewportWidth(newWidth)
                    }
                    .onChange(of: proxy.safeAreaInsets.top) { _, newTopInset in
                        updateTopObscuredHeight(newTopInset)
                    }
            }
        }
        .overlay {
            if shouldShowLoadingSkeleton {
                loadingView
                    .transition(loadingTransition)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !usesNativeFindNavigator && appState.showFindOnPage {
                FindOnPageBarView(
                    tabID: tabId,
                    availableWidth: max(articleViewportWidth - 32, 0)
                )
                    .padding(.top, findOnPageTopPadding)
                    .padding(.trailing, 16)
                    .transition(findTransition)
                    .zIndex(6)
            }
        }
        .overlay(alignment: .bottom) {
            // Show "Mark as read?" prompt when scrolled significantly and article is unread
            if showMarkAsReadPrompt && isArticleUnreadState {
                markAsReadPrompt
                    .transition(markPromptTransition)
                    .zIndex(5)
            }
        }
        .task(id: "\(tabId.uuidString)-\(article.id)") {
            articleLoader.cancelPendingMetadataHydration()
            pendingHydratedMetadata = nil
            updateLinkHoverPreview(nil)
            hasPublishedLiveReadingProgressForCurrentOpen = false
            articleLoader.cancelPendingPinSync()
            articleLoader.schedulePinSync(shouldPinArticleBodyCache, forArticleTitle: article.title)
            appState.setArticleHTMLPinned(shouldPinArticleBodyCache, forTitle: article.title)
            syncReadStateFromStore()
            if !appState.currentArticleTableOfContents.isEmpty {
                appState.currentArticleTableOfContents = []
            }
            if appState.pendingTableOfContentsScrollTarget != nil {
                appState.pendingTableOfContentsScrollTarget = nil
            }
            if appState.currentVisibleTableOfContentsSectionId != nil {
                appState.currentVisibleTableOfContentsSectionId = nil
            }
            if !appState.currentArticleReferences.isEmpty {
                appState.currentArticleReferences = []
            }
            if appState.selectedReferenceId != nil {
                appState.selectedReferenceId = nil
            }
            await loadArticle(preloadedHTML: appState.cachedArticleHTML(forTitle: article.title))
            // Reset prompt state for new article
            showMarkAsReadPrompt = false
            promptPolicy.resetForSession(startProgress: progressCoordinator.latestReadingProgress)
        }
        .onDisappear {
            progressCoordinator.persistCurrentProgress(for: article, in: modelContext, force: true)
            articleLoader.cancelPendingMetadataHydration()
            articleLoader.cancelPendingPinSync()
            pendingHydratedMetadata = nil
            updateLinkHoverPreview(nil)
            hasPublishedLiveReadingProgressForCurrentOpen = false
        }
        .onChange(of: article.title) { oldTitle, newTitle in
            guard oldTitle != newTitle else { return }
            // Same-tab article switches can reuse the view identity, so force-flush
            // the previous article's progress before task-driven state resets.
            let previousArticle = Article(id: oldTitle, title: oldTitle)
            let previousProgress = appState.liveReadingProgress(forTitle: oldTitle) ?? progressCoordinator.latestReadingProgress
            progressCoordinator.persist(progress: previousProgress, for: previousArticle, in: modelContext, force: true)
        }
        .onChange(of: appState.pendingHighlightArticleRefresh?.id) { _, _ in
            guard let request = appState.pendingHighlightArticleRefresh else { return }
            let requestTitle = ReadStateSync.normalizedTitle(request.articleTitle)
            guard requestTitle == ReadStateSync.normalizedTitle(article.title) else { return }
            Task {
                await refreshArticleForHighlightReconciliation(request: request)
            }
        }
        .onChange(of: appState.currentArticle?.isRead) { _, newValue in
            guard appState.currentArticle?.title == article.title,
                  let newValue else { return }
            isArticleUnreadState = !newValue
        }
        .onChange(of: scrollPosition) { oldValue, newValue in
            promptPolicy.noteScrollChange(oldValue: oldValue, newValue: newValue)
        }
        .onChange(of: shouldPinArticleBodyCache) { _, shouldPin in
            articleLoader.schedulePinSync(shouldPin, forArticleTitle: article.title)
            appState.setArticleHTMLPinned(shouldPin, forTitle: article.title)
        }
        .animation(
            reduceMotion ? nil : ReaderMotion.promptSpring,
            value: showMarkAsReadPrompt
        )
    }

    @ViewBuilder
    private var content: some View {
        if let error = errorMessage {
            errorView(error)
        } else if let html = htmlContent, loadedArticleKey == article.id {
            let webView = WebView(
                tabID: tabId,
                htmlContent: html,
                articleTitle: article.title,
                baseURL: URL(string: "https://en.wikipedia.org/wiki/"),
                onLinkTapped: { title in
                    openLinkedArticle(title: title)
                },
                onOpenArticleInNewWindow: { article in
                    openWindow(value: article)
                },
                onTextSelected: { selectionData in
                    appState.currentTextSelection = selectionData
                },
                onSelectionCleared: {
                    appState.currentTextSelection = nil
                },
                highlights: articleHighlights,
                scrollPosition: $scrollPosition,
                onScrollProgress: { progress in
                    updateReadingProgress(progress)
                },
                fallbackScrollProgress: progressCoordinator.latestReadingProgress,
                readerAppearance: resolvedReaderAppearance,
                readerTopInset: readerTopInset,
                preferImmediateReveal: preferImmediateWebReveal,
                onTableOfContentsUpdate: { toc in
                    guard appState.currentArticle?.title == article.title else { return }
                    if appState.currentArticleTableOfContents != toc {
                        appState.currentArticleTableOfContents = toc
                    }
                },
                onReferencesUpdate: { sections in
                    guard appState.currentArticle?.title == article.title else { return }
                    appState.currentArticleReferences = sections
                },
                onVisibleSectionChange: { sectionId in
                    guard appState.currentArticle?.title == article.title else { return }
                    if appState.currentVisibleTableOfContentsSectionId != sectionId {
                        appState.currentVisibleTableOfContentsSectionId = sectionId
                    }
                },
                onContentReveal: {
                    guard appState.currentArticle?.title == article.title else { return }
                    if !isWebContentReady {
                        if isLoadingSkeletonVisible {
                            performWebRevealAnimation {
                                isWebContentReady = true
                            }
                        } else {
                            isWebContentReady = true
                        }
                    }
                    openTimer.markRevealComplete()
                    hideLoadingSkeletonIfNeeded()
                    publishLiveReadingProgressIfNeeded()
                    applyPendingHydratedMetadataIfNeeded()
                },
                onContentLoadFailure: { error in
                    guard appState.currentArticle?.title == article.title else { return }
                    errorMessage = error.localizedDescription
                    isLoading = false
                    isWebContentReady = true
                    isLoadingSkeletonVisible = false
                },
                onLinkHoverPreviewChange: { request in
                    guard appState.currentArticle?.title == article.title || request == nil else { return }
                    updateLinkHoverPreview(request)
                },
                linkHoverPreviewOverlayHovering: isHoveringLinkHoverPreview,
                activeLinkHoverPreviewSignature: linkHoverPreviewRequest?.signature,
                linkPreviewImmediateModifier: linkPreviewImmediateModifier,
                nativeHighlightingMenuEnabled: false,
                openTimer: $openTimer,
                appState: appState,
                inspectorVisible: appState.inspectorVisible,
                inspectorMode: appState.inspectorMode,
                findOnPageRequestID: usesNativeFindNavigator ? nil : appState.pendingFindOnPageRequest?.requestID
            )
            .id(tabId)
            .clipped()
            .overlay(alignment: .topLeading) {
                if let request = linkHoverPreviewRequest {
                    ReaderLinkHoverPreviewOverlay(
                        request: request,
                        onOpen: {
                            openLinkHoverPreview(request, inNewTab: false)
                        },
                        onOpenInNewTab: {
                            openLinkHoverPreview(request, inNewTab: true)
                        },
                        onOpenInNewWindow: {
                            openLinkHoverPreviewInNewWindow(request)
                        },
                        onSave: {
                            saveLinkHoverPreview(request)
                        },
                        onReveal: {
                            scheduleLinkHoverRevealHapticIfNeeded()
                        },
                        onHoverStateChange: { hovering in
                            isHoveringLinkHoverPreview = hovering
                        }
                    )
                    .environment(appState)
                    .transition(linkHoverPreviewTransition)
                    .zIndex(7)
                }
            }
            .overlay {
                // Highlight toolbar overlay
                HighlightToolbarOverlay(articleTitle: article.title)
            }

            if #available(macOS 26, *) {
                webView
                    .findNavigator(isPresented: findNavigatorPresentedBinding)
            } else {
                webView
            }
        } else if isLoading {
            Color.clear
        } else {
            placeholderView
        }
    }

    private var markAsReadPrompt: some View {
        MacWikiGlassGroup(spacing: 7) {
            HStack(spacing: 12) {
                markAsReadIcon
                markAsReadCopy

                Spacer(minLength: 6)

                markAsReadActions
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(markAsReadPromptBackground)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.16 : 0.06), radius: 10, y: 4)
        .compositingGroup()
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var markAsReadIcon: some View {
        ZStack {
            markAsReadIconBackground
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary.opacity(colorScheme == .dark ? 0.72 : 0.60))
        }
        .frame(width: 30, height: 30)
    }

    private var markAsReadCopy: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Finished reading?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text("Save this article as complete.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var markAsReadActions: some View {
        HStack(spacing: 7) {
            Button {
                markAllAsRead()
                performPromptAnimation(
                    response: ReaderMotion.promptPrimaryDismissResponse,
                    dampingFraction: ReaderMotion.promptPrimaryDismissDamping
                ) {
                    showMarkAsReadPrompt = false
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                    Text("Mark as Read")
                        .font(.subheadline.weight(.semibold))
                }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            .background(markAsReadPrimaryActionBackground)

            Button {
                performPromptAnimation(
                    response: ReaderMotion.promptSecondaryDismissResponse,
                    dampingFraction: ReaderMotion.promptSecondaryDismissDamping
                ) {
                    showMarkAsReadPrompt = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 23, height: 23)
                    .background(markAsReadSecondaryActionBackground)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var markAsReadPromptBackground: some View {
        let shape = RoundedRectangle(cornerRadius: ReaderMotion.promptCornerRadius, style: .continuous)
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
           ) {
            shape
                .fill(.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: ReaderMotion.promptCornerRadius))
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.022 : 0.014))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.075 : 0.048), lineWidth: 0.50)
                }
        } else {
            shape
                .fill(.thinMaterial)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.10 : 0.06))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.09 : 0.055), lineWidth: 0.52)
                }
        }
    }

    @ViewBuilder
    private var markAsReadIconBackground: some View {
        let shape = Circle()
        shape
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.055))
            .overlay {
                shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.050 : 0.030), lineWidth: 0.45)
            }
    }

    private var markAsReadPrimaryStrokeOpacity: Double {
        colorScheme == .dark ? 0.075 : 0.046
    }

    @ViewBuilder
    private var markAsReadPrimaryActionBackground: some View {
        let shape = Capsule(style: .continuous)
        if #available(macOS 26, *),
           MacWikiGlassRuntime.usesNativeGlass(
            isEnabled: liquidGlassChrome,
            forceLegacyFallback: forceLegacyGlassFallback
           ) {
            shape
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay {
                    shape.fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.028 : 0.016))
                }
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(markAsReadPrimaryStrokeOpacity), lineWidth: 0.50)
                }
        } else {
            shape
                .fill(Color(nsColor: .windowBackgroundColor).opacity(colorScheme == .dark ? 0.16 : 0.09))
                .overlay {
                    shape.strokeBorder(Color.primary.opacity(markAsReadPrimaryStrokeOpacity), lineWidth: 0.50)
                }
        }
    }

    @ViewBuilder
    private var markAsReadSecondaryActionBackground: some View {
        let shape = Circle()
        shape
            .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.045))
            .overlay {
                shape.strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.048 : 0.030), lineWidth: 0.45)
            }
    }

    private func markAllAsRead() {
        progressCoordinator.markAsCompleted(for: article, in: modelContext, appState: appState)
        isArticleUnreadState = false
    }

    private func updateReadingProgress(_ progress: Double) {
        guard let clamped = progressCoordinator.consumeTelemetry(
            progress,
            for: article,
            in: modelContext,
            appState: appState,
            publishLiveProgress: hasPublishedLiveReadingProgressForCurrentOpen
        ) else {
            return
        }
        if promptPolicy.shouldShowPrompt(
            forProgress: clamped,
            isArticleUnread: isArticleUnreadState,
            isPromptAlreadyVisible: showMarkAsReadPrompt
        ) {
            performPromptAnimation(
                response: ReaderMotion.promptShowResponse,
                dampingFraction: ReaderMotion.promptShowDamping
            ) {
                showMarkAsReadPrompt = true
            }
        }
    }

    private func performPromptAnimation(
        response: Double,
        dampingFraction: Double,
        _ updates: () -> Void
    ) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: response, dampingFraction: dampingFraction), updates)
        }
    }

    private func performWebRevealAnimation(_ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: ReaderMotion.webRevealDuration), updates)
        }
    }

    private func performSkeletonAnimation(duration: Double, _ updates: () -> Void) {
        if reduceMotion {
            updates()
        } else {
            withAnimation(.easeOut(duration: duration), updates)
        }
    }

    private func syncReadStateFromStore() {
        let resolved = ReadStateSync.resolveReadState(for: article, in: modelContext)
        appState.updateReadState(forTitle: article.title, isRead: resolved)
        isArticleUnreadState = !resolved

        let now = Date().timeIntervalSinceReferenceDate
        if let existing = ReadStateSync.fetchArticleState(forURLString: article.url.absoluteString, in: modelContext) {
            let existingProgress = existing.readingProgress ?? 0
            progressCoordinator.bootstrapFromPersisted(existingProgress, articleTitle: article.title, appState: appState, now: now)
            ReadStateSync.syncSavedArticles(title: article.title, isRead: existing.isRead, in: modelContext)
            modelContext.saveReportingFailure(operation: #function)
        } else {
            progressCoordinator.bootstrapWithoutPersistedState(articleTitle: article.title, appState: appState, now: now)
        }
    }
    
    private var loadingView: some View {
        ArticleLoadingSkeletonView(
            articleTitle: article.title,
            phase: htmlContent == nil ? .fetching : .rendering
        )
        .allowsHitTesting(false)
    }

    private func updateTopObscuredHeight(_ newValue: CGFloat) {
        let resolved = max(0, newValue)
        guard abs(topObscuredHeight - resolved) > 0.5 else { return }
        topObscuredHeight = resolved
    }
    
    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            SwiftUI.Label("Failed to Load Article", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button("Try Again", systemImage: "arrow.clockwise") {
                Task {
                    await loadArticle(forceRefresh: true)
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }
    
    private var placeholderView: some View {
        ContentUnavailableView(
            article.title,
            systemImage: "doc.text",
            description: Text(article.description ?? "")
        )
    }
    
    @MainActor
    private func refreshArticleForHighlightReconciliation(
        request: AppState.HighlightArticleRefreshRequest
    ) async {
        guard !appState.isHighlightArticleRefreshInProgress else { return }
        appState.isHighlightArticleRefreshInProgress = true
        appState.lastHighlightArticleRefreshResult = nil

        defer {
            if appState.pendingHighlightArticleRefresh?.id == request.id {
                appState.pendingHighlightArticleRefresh = nil
            }
            appState.isHighlightArticleRefreshInProgress = false
        }

        let refreshSucceeded = await loadArticle(forceRefresh: true)
        appState.lastHighlightArticleRefreshResult = AppState.HighlightArticleRefreshResult(
            requestId: request.id,
            articleTitle: article.title,
            success: refreshSucceeded,
            timestamp: Date()
        )
    }

    @discardableResult
    private func loadArticle(preloadedHTML: String? = nil, forceRefresh: Bool = false) async -> Bool {
        let resolvedPreloadedHTML = forceRefresh ? nil : preloadedHTML
        let hasReusableWebSurface = !forceRefresh && WebViewPool.shared.hasReusableWebView(for: tabId)
        let shouldPreserveVisibleContent =
            forceRefresh &&
            htmlContent != nil &&
            loadedArticleKey == article.id

        if shouldPreserveVisibleContent {
            skeletonVisibilityTicket = UUID()
            isLoadingSkeletonVisible = false
            suppressLoadingSkeletonForCurrentOpen = true
            isLoading = false
            isWebContentReady = true
        } else {
            loadedArticleKey = nil
            isWebContentReady = false
            hasPublishedLiveReadingProgressForCurrentOpen = false
            isLoadingSkeletonVisible = false
            suppressLoadingSkeletonForCurrentOpen = hasReusableWebSurface
            openTimer.begin(title: article.title, preloaded: resolvedPreloadedHTML != nil)
            scheduleLoadingSkeletonAppearance(
                preloaded: resolvedPreloadedHTML != nil,
                suppressed: hasReusableWebSurface
            )
        }
        if let preloadedHTML = resolvedPreloadedHTML {
            htmlContent = preloadedHTML
            loadedArticleKey = article.id
            preferImmediateWebReveal = true
            isLoading = false
            openTimer.markHTMLBound()
        } else if !shouldPreserveVisibleContent {
            htmlContent = nil
            preferImmediateWebReveal = false
            isLoading = true
        }
        errorMessage = nil
        pendingHydratedMetadata = nil
        if !shouldPreserveVisibleContent, !appState.currentArticleMetadata.isEmpty {
            appState.currentArticleMetadata = []
        }

        do {
            let content = try await articleLoader.fetchFastContent(
                forTitle: article.title,
                forceRefresh: forceRefresh
            )
            openTimer.markFetchComplete(source: content.source)
            let shouldRevealImmediately = content.isWarmCacheHit || resolvedPreloadedHTML != nil
            if preferImmediateWebReveal != shouldRevealImmediately {
                preferImmediateWebReveal = shouldRevealImmediately
            }

            if forceRefresh {
                if htmlContent != content.html {
                    htmlContent = content.html
                    loadedArticleKey = article.id
                    openTimer.markHTMLBound()
                    isWebContentReady = false
                    preferImmediateWebReveal = content.isWarmCacheHit
                } else if loadedArticleKey != article.id {
                    loadedArticleKey = article.id
                }
            } else if htmlContent == nil {
                htmlContent = content.html
                loadedArticleKey = article.id
                openTimer.markHTMLBound()
            }
            isLoading = false
            cacheArticleHTMLSizeAware(content.html, title: article.title)
            appState.currentArticleMetadata = content.metadata
            articleLoader.scheduleMetadataHydration(
                for: article,
                html: content.html,
                wordCount: content.wordCount
            ) { enriched in
                guard appState.currentArticle?.title == article.title else { return }
                let hydrated = PendingHydratedMetadata(
                    articleID: article.id,
                    articleTitle: article.title,
                    items: enriched.items,
                    wordCount: enriched.wordCount
                )
                if isWebContentReady {
                    applyHydratedMetadata(hydrated)
                } else {
                    pendingHydratedMetadata = hydrated
                }
            }
            return true
        } catch {
            if error is CancellationError {
                return false
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return false
            }
            guard !Task.isCancelled else { return false }

            if !shouldPreserveVisibleContent {
                loadedArticleKey = nil
                errorMessage = error.localizedDescription
            }
            preferImmediateWebReveal = false
            isLoading = false
            isWebContentReady = true
            isLoadingSkeletonVisible = false
            return false
        }
    }

    private func applyPendingHydratedMetadataIfNeeded() {
        guard let pending = pendingHydratedMetadata,
              pending.articleID == article.id,
              pending.articleTitle == article.title else {
            return
        }

        pendingHydratedMetadata = nil
        applyHydratedMetadata(pending)
    }

    private func applyHydratedMetadata(_ hydrated: PendingHydratedMetadata) {
        guard appState.currentArticle?.title == hydrated.articleTitle else { return }

        appState.currentArticleMetadata = hydrated.items
        appState.updateArticleMetadata(
            id: hydrated.articleID,
            description: nil,
            extract: nil,
            wordCount: hydrated.wordCount
        )
    }

    private func publishLiveReadingProgressIfNeeded() {
        guard !hasPublishedLiveReadingProgressForCurrentOpen else { return }
        hasPublishedLiveReadingProgressForCurrentOpen = true
        progressCoordinator.publishLatestProgress(for: article, appState: appState)
    }

    private func scheduleLoadingSkeletonAppearance(preloaded: Bool, suppressed: Bool) {
        if suppressed {
            return
        }
        let ticket = UUID()
        skeletonVisibilityTicket = ticket
        let delay: TimeInterval = preloaded ? 0.26 : 0.16

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard skeletonVisibilityTicket == ticket else { return }
            guard errorMessage == nil else { return }
            guard isLoading || !isWebContentReady else { return }
            loadingSkeletonShownAt = Date().timeIntervalSinceReferenceDate
            performSkeletonAnimation(duration: ReaderMotion.skeletonRevealDuration) {
                isLoadingSkeletonVisible = true
            }
        }
    }

    private func hideLoadingSkeletonIfNeeded() {
        guard isLoadingSkeletonVisible else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let minVisibleDuration = AppLoadingMotion.skeletonMinimumVisibleDuration
        let elapsed = now - loadingSkeletonShownAt
        let remaining = max(0, minVisibleDuration - elapsed)
        let ticket = skeletonVisibilityTicket

        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard skeletonVisibilityTicket == ticket else { return }
            performSkeletonAnimation(duration: ReaderMotion.skeletonHideDuration) {
                isLoadingSkeletonVisible = false
            }
        }
    }
    
    private func cacheArticleHTMLSizeAware(_ html: String, title: String) {
        // Keep very large payload copies off the immediate open critical path.
        let htmlByteCount = html.utf8.count
        if htmlByteCount <= 420_000 {
            appState.cacheArticleHTML(html, forTitle: title)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            appState.cacheArticleHTML(html, forTitle: title)
        }
    }
    
    private func openLinkedArticle(title: String) {
        let linkedArticle = Article(id: title, title: title)
        appState.openArticle(linkedArticle, inNewTab: false)
    }

    private func openLinkHoverPreview(_ request: WebViewLinkHoverRequest, inNewTab: Bool) {
        updateLinkHoverPreview(nil)
        guard let article = hoverPreviewArticle(for: request) else {
            _ = SystemBridge.openURLExternally(request.url)
            return
        }

        if inNewTab {
            appState.openArticleInNewTab(article)
        } else {
            appState.openArticle(article, inNewTab: false)
        }
    }

    private func openLinkHoverPreviewInNewWindow(_ request: WebViewLinkHoverRequest) {
        updateLinkHoverPreview(nil)
        guard let article = hoverPreviewArticle(for: request) else {
            _ = SystemBridge.openURLExternally(request.url)
            return
        }

        openWindow(value: article)
    }

    private func saveLinkHoverPreview(_ request: WebViewLinkHoverRequest) {
        updateLinkHoverPreview(nil)
        guard let article = hoverPreviewArticle(for: request) else { return }
        appState.presentOptionClickSavePrompt(for: article)
    }

    private func hoverPreviewArticle(for request: WebViewLinkHoverRequest) -> Article? {
        guard let rawTitle = request.articleTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawTitle.isEmpty else {
            return nil
        }
        return Article(id: rawTitle, title: rawTitle)
    }

    private func updateLinkHoverPreview(_ request: WebViewLinkHoverRequest?) {
        let updates = {
            linkHoverPreviewRequest = request
            if request == nil {
                pendingLinkHoverRevealHapticTask?.cancel()
                pendingLinkHoverRevealHapticTask = nil
                isHoveringLinkHoverPreview = false
            }
        }

        if reduceMotion {
            updates()
        } else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.90, blendDuration: 0.04), updates)
        }
    }

    private func scheduleLinkHoverRevealHapticIfNeeded() {
        pendingLinkHoverRevealHapticTask?.cancel()

        let delay = reduceMotion ? 0 : ReaderMotion.hoverPreviewHapticDelay
        pendingLinkHoverRevealHapticTask = Task { @MainActor in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }

            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastLinkHoverRevealHapticTimestamp >= ReaderMotion.hoverPreviewHapticCooldown else { return }
            lastLinkHoverRevealHapticTimestamp = now
            pendingLinkHoverRevealHapticTask = nil
        }
    }

    private func updateArticleViewportWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        guard abs(articleViewportWidth - width) >= 0.5 else { return }
        articleViewportWidth = width
    }

}
