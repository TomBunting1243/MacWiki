import SwiftUI
import SwiftData

private enum ReaderMotion {
    static let surfaceSwap = Animation.easeOut(duration: 0.22)
    static let surfaceInsertionScale: CGFloat = 0.995
    static let webRevealDuration: Double = 0.20
    static let skeletonRevealDuration: Double = AppLoadingMotion.skeletonRevealDuration
    static let skeletonHideDuration: Double = AppLoadingMotion.skeletonHideDuration
    static let promptSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
    static let promptShowResponse: Double = 0.30
    static let promptShowDamping: Double = 0.82
    static let promptPrimaryDismissResponse: Double = 0.26
    static let promptPrimaryDismissDamping: Double = 0.84
    static let promptSecondaryDismissResponse: Double = 0.22
    static let promptSecondaryDismissDamping: Double = 0.88
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
                let activeHistoryItemID = activeTab.history.indices.contains(activeTab.currentIndex)
                    ? activeTab.history[activeTab.currentIndex].id
                    : nil

                if activeTab.isNewTab {
                    // Show new tab page with search
                    NewTabPageView()
                } else {
                    // Show article content
                    ArticleView(
                        tabId: activeId,
                        article: activeTab.article,
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
            WebViewPool.shared.retain(only: Set(appState.openTabs.map(\.id)))
        }
        .onChange(of: appState.openTabs.map(\.id)) { _, tabIDs in
            WebViewPool.shared.retain(only: Set(tabIDs))
        }
    }

    private var activeReaderSurfaceID: String {
        guard let activeId = appState.activeTabId,
              let tab = appState.openTabs.first(where: { $0.id == activeId }) else {
            return "reader-surface-empty"
        }

        if tab.isNewTab {
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

/// Quick search overlay with live Wikipedia search

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @AppStorage(ReaderAppearanceStorageKey.fontPreset) private var readerFontPreset: ReaderFontPreset = .system
    @AppStorage(ReaderAppearanceStorageKey.fontSize) private var readerFontSize: Double = ReaderAppearance.default.fontSize
    @AppStorage(ReaderAppearanceStorageKey.lineHeight) private var readerLineHeight: Double = ReaderAppearance.default.lineHeight
    @AppStorage(ReaderAppearanceStorageKey.paragraphSpacing) private var readerParagraphSpacing: Double = ReaderAppearance.default.paragraphSpacing
    @AppStorage(ReaderAppearanceStorageKey.contentWidth) private var readerContentWidth: Double = ReaderAppearance.default.contentWidth
    @AppStorage(ReaderAppearanceStorageKey.horizontalPadding) private var readerHorizontalPadding: Double = ReaderAppearance.default.horizontalPadding
    @AppStorage(ReaderAppearanceStorageKey.headingScale) private var readerHeadingScale: Double = ReaderAppearance.default.headingScale
    @AppStorage("tabBarLiquidGlass") private var tabBarLiquidGlass = true
    @AppStorage("nativeHighlightingMenuEnabled") private var nativeHighlightingMenuEnabled = false

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

    private var effectiveReaderAppearance: ReaderAppearance {
        guard appState.isFocusModeEnabled else { return readerAppearance }
        return ReaderAppearance(
            fontPreset: readerFontPreset,
            fontSize: readerFontSize,
            lineHeight: readerLineHeight,
            paragraphSpacing: readerParagraphSpacing,
            // Keep article content effectively unconstrained in focus mode.
            contentWidth: 10_000,
            // Preserve edge breathing room while maximizing line real estate.
            horizontalPadding: 16,
            headingScale: readerHeadingScale
        )
    }

    private var resolvedReaderAppearance: ReaderAppearance {
        effectiveReaderAppearance.resolvedForViewportWidth(Double(articleViewportWidth))
    }

    private var readerTopInset: CGFloat {
        let hasToolbarControls = !appState.isWikiHopNavigationLocked && !appState.isFocusModeEnabled
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
            // In liquid-glass mode the top chrome overlays the reader, so keep
            // a modest inset that allows visible underflow beneath the glass.
            resolved = tabBarLiquidGlass
                ? ColumnChromeMetrics.readerContentTopInset(
                    windowTopObscuredHeight: appState.windowTopObscuredHeight,
                    additionalSpacing: 14 + compactWidthBoost
                )
                : (92 + compactWidthBoost)
        } else {
            resolved = max(0, appState.windowTopObscuredHeight) + 8
        }
        return max(resolved, 0)
    }

    private var findOnPageTopPadding: CGFloat {
        let compactWidthBoost: CGFloat
        switch articleViewportWidth {
        case ..<680:
            compactWidthBoost = 4
        default:
            compactWidthBoost = 0
        }
        if tabBarLiquidGlass &&
            !appState.isWikiHopNavigationLocked &&
            !appState.isFocusModeEnabled {
            // Clear the full liquid reader chrome stack (titlebar spacer + toolbar + tab lane).
            return ColumnChromeMetrics.readerChromeOverlayHeight(
                windowTopObscuredHeight: appState.windowTopObscuredHeight
            ) + 8 + compactWidthBoost
        }
        return 10 + compactWidthBoost
    }

    private var focusTOCOverlayBottomPadding: CGFloat {
        let base: CGFloat = 14
        if showMarkAsReadPrompt && isArticleUnreadState {
            return base + 64
        }
        return base
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

    private var focusTOCTransition: AnyTransition {
        reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity)
    }

    private var markPromptTransition: AnyTransition {
        reduceMotion ? .identity : .move(edge: .bottom).combined(with: .opacity)
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
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateArticleViewportWidth(newWidth)
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
            if appState.showFindOnPage && !appState.isFocusModeEnabled {
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
        .overlay(alignment: .bottomLeading) {
            if appState.isFocusModeEnabled {
                ReaderFocusTOCView(items: appState.currentArticleTableOfContents)
                    .padding(.bottom, focusTOCOverlayBottomPadding)
                    .padding(.leading, 14)
                    .transition(focusTOCTransition)
                    .zIndex(7)
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
        .onChange(of: nativeHighlightingMenuEnabled) { _, enabled in
            if enabled {
                appState.currentTextSelection = nil
            }
        }
        .animation(
            reduceMotion ? nil : ReaderMotion.promptSpring,
            value: showMarkAsReadPrompt
        )
        .onExitCommand {
            guard appState.isFocusModeEnabled else { return }
            appState.setFocusModeEnabled(false)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error = errorMessage {
            errorView(error)
        } else if let html = htmlContent, loadedArticleKey == article.id {
            WebView(
                tabID: tabId,
                htmlContent: html,
                articleTitle: article.title,
                baseURL: URL(string: "https://en.wikipedia.org/wiki/"),
                onLinkTapped: { title in
                    openLinkedArticle(title: title)
                },
                onTextSelected: { selectionData in
                    if nativeHighlightingMenuEnabled {
                        appState.currentTextSelection = nil
                    } else {
                        appState.currentTextSelection = selectionData
                    }
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
                    if appState.currentArticleReferences != sections {
                        appState.currentArticleReferences = sections
                    }
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
                nativeHighlightingMenuEnabled: nativeHighlightingMenuEnabled,
                openTimer: $openTimer,
                appState: appState,
                inspectorVisible: appState.inspectorVisible,
                inspectorMode: appState.inspectorMode,
                focusModeEnabled: appState.isFocusModeEnabled,
                findOnPageRequestID: appState.pendingFindOnPageRequest?.requestID
            )
            .id(tabId)
            .clipped()
            .overlay {
                // Highlight toolbar overlay
                if !nativeHighlightingMenuEnabled {
                    HighlightToolbarOverlay(articleTitle: article.title)
                }
            }
        } else if isLoading {
            Color.clear
        } else {
            placeholderView
        }
    }

    private var markAsReadPrompt: some View {
        HStack(spacing: 12) {
            markAsReadIcon
            markAsReadCopy

            Spacer(minLength: 6)

            markAsReadActions
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(colorScheme == .dark ? 0.17 : 0.32),
                                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.11),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.screen)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.20 : 0.33), lineWidth: 1.0)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .inset(by: 0.7)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.32 : 0.48),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.34 : 0.16), radius: 22, y: 10)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 7, y: 2)
        .compositingGroup()
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var markAsReadIcon: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.24 : 0.42),
                            Color.white.opacity(0.02)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.30), lineWidth: 0.8)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
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
            .background(
                Capsule(style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(colorScheme == .dark ? 0.20 : 0.34),
                                        Color.white.opacity(0.01)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.30), lineWidth: 0.8)
                    )
            )

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
                    .background(.regularMaterial, in: Circle())
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.24), lineWidth: 0.75)
                    )
            }
            .buttonStyle(.plain)
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
            try? modelContext.save()
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
    
    private func errorView(_ error: String) -> some View {
        ContentUnavailableView(
            "Failed to Load Article",
            systemImage: "exclamationmark.triangle",
            description: Text(error)
        )
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

        await loadArticle(forceRefresh: true)
        appState.lastHighlightArticleRefreshResult = AppState.HighlightArticleRefreshResult(
            requestId: request.id,
            articleTitle: article.title,
            success: errorMessage == nil,
            timestamp: Date()
        )
    }

    private func loadArticle(preloadedHTML: String? = nil, forceRefresh: Bool = false) async {
        let resolvedPreloadedHTML = forceRefresh ? nil : preloadedHTML
        let hasReusableWebSurface = !forceRefresh && WebViewPool.shared.hasReusableWebView(for: tabId)
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
        if let preloadedHTML = resolvedPreloadedHTML {
            htmlContent = preloadedHTML
            loadedArticleKey = article.id
            preferImmediateWebReveal = true
            isLoading = false
            openTimer.markHTMLBound()
        } else {
            htmlContent = nil
            preferImmediateWebReveal = false
            isLoading = true
        }
        errorMessage = nil
        pendingHydratedMetadata = nil
        if !appState.currentArticleMetadata.isEmpty {
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

            if htmlContent == nil {
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
        } catch {
            if error is CancellationError {
                return
            }
            if let urlError = error as? URLError, urlError.code == .cancelled {
                return
            }
            guard !Task.isCancelled else { return }

            loadedArticleKey = nil
            errorMessage = error.localizedDescription
            preferImmediateWebReveal = false
            isLoading = false
            isWebContentReady = true
            isLoadingSkeletonVisible = false
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

    private func updateArticleViewportWidth(_ width: CGFloat) {
        guard width > 0 else { return }
        guard abs(articleViewportWidth - width) >= 0.5 else { return }
        articleViewportWidth = width
    }

}
